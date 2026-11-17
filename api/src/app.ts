import { Hono, type Context, type MiddlewareHandler } from "hono";
import { bodyLimit } from "hono/body-limit";
import { HTTPException } from "hono/http-exception";
import { z } from "zod";

import {
  SESSION_TTL_MS,
  hashSessionToken,
  newSessionToken,
  type GoogleTokenVerifier,
} from "./auth";
import {
  revenueCatWebhook,
  webhookAuthorized,
  webhookCustomerIds,
  type BillingProvider,
} from "./billing";
import type { FolderRow, PaletteRow, UserRow } from "./db/schema";
import { MAX_FOLDERS, hasStorePro, isPro, paletteLimit, proEndsAt } from "./plan";
import type { Store } from "./store";

// ---------------------------------------------------------------------------
// Request validation
// ---------------------------------------------------------------------------

/** Accepts "#AABBCC" or "aabbcc"; stores "aabbcc". */
const hex = z
  .string()
  .trim()
  .regex(/^#?[0-9a-fA-F]{6}$/, "must be a 6-digit hex color")
  .transform((s) => s.replace("#", "").toLowerCase());

const color = z.object({
  hex,
  name: z.string().trim().min(1).max(80),
  textColor: hex,
});

const paletteName = z.string().trim().min(1).max(60);

/** Inner whitespace collapsed; duplicates (ignoring case) dropped, first kept. */
const tags = z
  .array(
    z
      .string()
      .trim()
      .min(1)
      .max(30)
      .transform((t) => t.replace(/\s+/g, " ")),
  )
  .max(10)
  .transform((list) => {
    const seen = new Set<string>();
    return list.filter((t) => {
      const key = t.toLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  });

const folderRef = z.uuid().nullable();

const paletteInput = z.object({
  name: paletteName,
  kind: z.enum(["palette", "gradient"]).default("palette"),
  colors: z.array(color).min(1).max(12),
  folderId: folderRef.optional(),
  tags: tags.optional(),
});

const paletteUpdate = z
  .object({
    name: paletteName.optional(),
    folderId: folderRef.optional(),
    tags: tags.optional(),
  })
  .refine((u) => Object.values(u).some((v) => v !== undefined), {
    message: "Nothing to update",
  });

const folderInput = z.object({ name: z.string().trim().min(1).max(40) });

const googleSignInInput = z.object({ idToken: z.string().min(1).max(8192) });

const resourceId = z.uuid();

async function parseBody<S extends z.ZodType>(
  c: Context,
  schema: S,
): Promise<z.output<S>> {
  let json: unknown;
  try {
    json = await c.req.json();
  } catch {
    throw new HTTPException(400, { message: "Request body must be JSON" });
  }
  const result = schema.safeParse(json);
  if (!result.success) {
    throw new HTTPException(400, { message: z.prettifyError(result.error) });
  }
  return result.data;
}

const PALETTE_NOT_FOUND = "Palette not found";
const FOLDER_NOT_FOUND = "Folder not found";

function parseId(c: Context, notFound: string): string {
  const result = resourceId.safeParse(c.req.param("id"));
  // A malformed id can't belong to the caller, so it's a 404, not a 400.
  if (!result.success) throw new HTTPException(404, { message: notFound });
  return result.data;
}

// ---------------------------------------------------------------------------
// Pro
// ---------------------------------------------------------------------------

/**
 * 402 with a machine-readable `code` the app uses to show the upgrade screen:
 * "pro_required" for Pro-only actions, "palette_limit" for a full free library.
 */
function upgradeRequired(
  c: Context,
  code: "pro_required" | "palette_limit",
  error: string,
  extra: Record<string, unknown> = {},
) {
  return c.json({ error, code, ...extra }, 402);
}

/** Filing into a folder or adding tags is Pro; taking them away never is. */
function organizes(input: { folderId?: string | null; tags?: string[] }): boolean {
  return (input.folderId ?? null) !== null || (input.tags?.length ?? 0) > 0;
}

const ORGANIZE_IS_PRO = "Folders and tags are part of Color Blendr Pro.";

// ---------------------------------------------------------------------------
// Responses: never expose internal ids like google_sub or token hashes
// ---------------------------------------------------------------------------

function userDto(row: UserRow, now: Date) {
  const pro = isPro(row, now);
  return {
    id: row.id,
    email: row.email,
    name: row.name,
    avatarUrl: row.avatarUrl,
    plan: pro ? "pro" : "free",
    /** Null when free, or when Pro doesn't end. */
    proExpiresAt: pro ? (proEndsAt(row, now)?.toISOString() ?? null) : null,
    limits: { palettes: paletteLimit(row, now) },
    /** The Google Play subscription behind Pro, if any (for "Manage subscription"). */
    subscription: hasStorePro(row, now)
      ? {
          productId: row.storeProductId,
          expiresAt: row.storeProExpiresAt?.toISOString() ?? null,
          willRenew: row.storeWillRenew,
          billingIssue: row.storeBillingIssue,
        }
      : null,
  };
}

function paletteDto(row: PaletteRow) {
  return {
    id: row.id,
    name: row.name,
    kind: row.kind,
    colors: row.colors,
    folderId: row.folderId,
    tags: row.tags,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
  };
}

function folderDto(row: FolderRow) {
  return { id: row.id, name: row.name, createdAt: row.createdAt.toISOString() };
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

export type BillingDeps = {
  provider: BillingProvider;
  /** Shared secret RevenueCat sends as `Authorization: Bearer <secret>`. */
  webhookSecret: string;
  /**
   * Lowercased emails of developer test accounts, whose Test Store and other
   * sandbox purchases count. Everyone else needs a real store purchase.
   */
  testerEmails?: ReadonlySet<string>;
};

/** How often the app may make the API re-ask RevenueCat about one user. */
export const SYNC_COOLDOWN_MS = 10_000;

/** Upper bound on customers one webhook can make us re-read. */
const MAX_WEBHOOK_CUSTOMERS = 10;

export type AppDeps = {
  store: Store;
  verifyGoogleToken: GoogleTokenVerifier;
  /** Omit to run without purchases (billing routes answer 503). */
  billing?: BillingDeps;
  /** Injectable for tests. */
  now?: () => Date;
};

type Env = { Variables: { user: UserRow; tokenHash: string } };

export function createApp({
  store,
  verifyGoogleToken,
  billing,
  now = () => new Date(),
}: AppDeps) {
  const app = new Hono<Env>();

  app.onError((err, c) => {
    if (err instanceof HTTPException) {
      return c.json({ error: err.message }, err.status);
    }
    console.error("Unhandled error", err);
    return c.json({ error: "Internal server error" }, 500);
  });

  app.notFound((c) => c.json({ error: "Not found" }, 404));

  app.get("/health", (c) => c.json({ ok: true }));

  app.use(
    "/v1/*",
    bodyLimit({
      maxSize: 256 * 1024,
      onError: (c) => c.json({ error: "Request body too large" }, 413),
    }),
  );

  /** Resolves `Authorization: Bearer <session token>` to a user, or 401s. */
  const requireUser: MiddlewareHandler<Env> = async (c, next) => {
    const header = c.req.header("authorization");
    if (!header?.toLowerCase().startsWith("bearer ")) {
      return c.json({ error: "Unauthorized" }, 401);
    }
    const tokenHash = hashSessionToken(header.slice(7).trim());
    const user = await store.findSessionUser(tokenHash);
    if (!user) return c.json({ error: "Unauthorized" }, 401);
    c.set("user", user);
    c.set("tokenHash", tokenHash);
    await next();
  };

  // --- Auth -----------------------------------------------------------------

  // Exchange a Google ID token (from the app's Google Sign-In) for a session.
  app.post("/v1/auth/google", async (c) => {
    const { idToken } = await parseBody(c, googleSignInInput);
    const identity = await verifyGoogleToken(idToken);
    if (!identity) return c.json({ error: "Invalid Google sign-in" }, 401);

    const user = await store.upsertGoogleUser(identity);
    const token = newSessionToken();
    const expiresAt = new Date(now().getTime() + SESSION_TTL_MS);
    await store.createSession(user.id, hashSessionToken(token), expiresAt);

    return c.json({ token, expiresAt: expiresAt.toISOString(), user: userDto(user, now()) });
  });

  app.delete("/v1/auth/session", requireUser, async (c) => {
    await store.deleteSession(c.get("tokenHash"));
    return c.body(null, 204);
  });

  // --- Account --------------------------------------------------------------

  app.get("/v1/me", requireUser, (c) => c.json(userDto(c.get("user"), now())));

  // Account deletion (required by Google Play): removes the user, their
  // sessions, palettes and folders.
  // Deleting the account does not cancel a Google Play subscription; the app
  // must tell the user to cancel it in Play (see docs/monetization.md).
  app.delete("/v1/me", requireUser, async (c) => {
    const userId = c.get("user").id;
    await store.deleteUser(userId);
    if (billing) {
      try {
        await billing.provider.deleteCustomer(userId);
      } catch (err) {
        // The account is gone either way; RevenueCat only holds a random id.
        console.error("RevenueCat customer deletion failed", err);
      }
    }
    return c.body(null, 204);
  });

  // --- Billing (Google Play via RevenueCat) ---------------------------------

  const BILLING_OFF = { error: "Purchases are not available right now" };

  /**
   * Re-reads the user's purchase from RevenueCat and saves it. Null if there's
   * no such user (e.g. a RevenueCat anonymous id, or a deleted account).
   */
  async function syncFromRevenueCat({ provider, testerEmails }: BillingDeps, userId: string) {
    if (!resourceId.safeParse(userId).success) return null;
    const user = await store.findUserById(userId);
    if (!user) return null;
    const checkedAt = now();
    const tester = testerEmails?.has(user.email.toLowerCase()) ?? false;
    const entitlement = await provider.getEntitlement(userId, checkedAt, { tester });
    return store.setStoreEntitlement(userId, entitlement, checkedAt);
  }

  // Called by the app right after a purchase, so Pro
  // shows up without waiting for the webhook. The request carries nothing but
  // the session: the answer comes from RevenueCat, never from the app.
  app.post("/v1/billing/sync", requireUser, async (c) => {
    if (!billing) return c.json(BILLING_OFF, 503);
    const user = c.get("user");
    const last = user.storeSyncedAt?.getTime() ?? 0;
    if (now().getTime() - last < SYNC_COOLDOWN_MS) return c.json(userDto(user, now()));
    const updated = (await syncFromRevenueCat(billing, user.id)) ?? user;
    return c.json(userDto(updated, now()));
  });

  // RevenueCat webhook. The payload is only a hint about whom to re-read;
  // errors return 500 so RevenueCat retries.
  app.post("/v1/billing/revenuecat", async (c) => {
    if (!billing) return c.json(BILLING_OFF, 503);
    if (!webhookAuthorized(c.req.header("authorization"), billing.webhookSecret)) {
      return c.json({ error: "Unauthorized" }, 401);
    }
    const { event } = await parseBody(c, revenueCatWebhook);
    await store.recordBillingEvent({
      id: event.id,
      type: event.type,
      appUserId: event.app_user_id ?? null,
      environment: event.environment ?? null,
    });
    const ids = webhookCustomerIds(event).slice(0, MAX_WEBHOOK_CUSTOMERS);
    for (const id of ids) await syncFromRevenueCat(billing, id);
    return c.json({ ok: true });
  });

  // --- Palettes -------------------------------------------------------------

  app.get("/v1/palettes", requireUser, async (c) => {
    const rows = await store.listPalettes(c.get("user").id);
    return c.json({ palettes: rows.map(paletteDto) });
  });

  app.post("/v1/palettes", requireUser, async (c) => {
    const input = await parseBody(c, paletteInput);
    const user = c.get("user");
    if (organizes(input) && !isPro(user, now())) {
      return upgradeRequired(c, "pro_required", ORGANIZE_IS_PRO);
    }
    const limit = paletteLimit(user, now());
    const result = await store.createPalette(user.id, input, limit);
    if (!result.ok) {
      if (result.reason === "folder_not_found") {
        throw new HTTPException(404, { message: FOLDER_NOT_FOUND });
      }
      return upgradeRequired(
        c,
        "palette_limit",
        `Free accounts can keep ${limit} palettes. Upgrade to Pro for unlimited saves.`,
        { limit },
      );
    }
    return c.json(paletteDto(result.row), 201);
  });

  // Rename, file into a folder (or out of it with null), or replace the tags.
  app.patch("/v1/palettes/:id", requireUser, async (c) => {
    const id = parseId(c, PALETTE_NOT_FOUND);
    const patch = await parseBody(c, paletteUpdate);
    const user = c.get("user");
    if (organizes(patch) && !isPro(user, now())) {
      return upgradeRequired(c, "pro_required", ORGANIZE_IS_PRO);
    }
    const result = await store.updatePalette(user.id, id, patch);
    if (!result.ok) {
      throw new HTTPException(404, {
        message: result.reason === "folder_not_found" ? FOLDER_NOT_FOUND : PALETTE_NOT_FOUND,
      });
    }
    return c.json(paletteDto(result.row));
  });

  app.delete("/v1/palettes/:id", requireUser, async (c) => {
    const id = parseId(c, PALETTE_NOT_FOUND);
    const removed = await store.deletePalette(c.get("user").id, id);
    if (!removed) throw new HTTPException(404, { message: PALETTE_NOT_FOUND });
    return c.body(null, 204);
  });

  // --- Folders: Pro to create or rename; anyone can list or delete ----------

  const DUPLICATE_FOLDER = "You already have a folder with that name";

  app.get("/v1/folders", requireUser, async (c) => {
    const rows = await store.listFolders(c.get("user").id);
    return c.json({ folders: rows.map(folderDto) });
  });

  app.post("/v1/folders", requireUser, async (c) => {
    const { name } = await parseBody(c, folderInput);
    const user = c.get("user");
    if (!isPro(user, now())) return upgradeRequired(c, "pro_required", ORGANIZE_IS_PRO);
    const result = await store.createFolder(user.id, name, MAX_FOLDERS);
    if (!result.ok) {
      throw new HTTPException(409, {
        message:
          result.reason === "duplicate"
            ? DUPLICATE_FOLDER
            : `You can have up to ${MAX_FOLDERS} folders`,
      });
    }
    return c.json(folderDto(result.row), 201);
  });

  app.patch("/v1/folders/:id", requireUser, async (c) => {
    const id = parseId(c, FOLDER_NOT_FOUND);
    const { name } = await parseBody(c, folderInput);
    const user = c.get("user");
    if (!isPro(user, now())) return upgradeRequired(c, "pro_required", ORGANIZE_IS_PRO);
    const result = await store.renameFolder(user.id, id, name);
    if (!result.ok) {
      if (result.reason === "duplicate") {
        throw new HTTPException(409, { message: DUPLICATE_FOLDER });
      }
      throw new HTTPException(404, { message: FOLDER_NOT_FOUND });
    }
    return c.json(folderDto(result.row));
  });

  // Its palettes stay in the library, unfiled.
  app.delete("/v1/folders/:id", requireUser, async (c) => {
    const id = parseId(c, FOLDER_NOT_FOUND);
    const removed = await store.deleteFolder(c.get("user").id, id);
    if (!removed) throw new HTTPException(404, { message: FOLDER_NOT_FOUND });
    return c.body(null, 204);
  });

  return app;
}
