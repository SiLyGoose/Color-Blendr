import { and, asc, count, desc, eq, gt, isNull, lte, or, sql } from "drizzle-orm";
import type { NodePgDatabase } from "drizzle-orm/node-postgres";

import type { GoogleIdentity } from "./auth";
import type { StoreEntitlement } from "./billing";
import {
  billingEvents,
  folders,
  palettes,
  sessions,
  users,
  type BillingEventRow,
  type FolderRow,
  type PaletteColor,
  type PaletteRow,
  type UserRow,
} from "./db/schema";

export type PaletteKind = "palette" | "gradient";

export type PaletteInput = {
  name: string;
  kind: PaletteKind;
  colors: PaletteColor[];
  folderId?: string | null;
  tags?: string[];
};

/** Fields a palette update may change; absent fields are left alone. */
export type PalettePatch = {
  name?: string;
  folderId?: string | null;
  tags?: string[];
};

/** Outcome of a write that can be refused for a reason the caller reports. */
export type Result<T, R extends string> = { ok: true; row: T } | { ok: false; reason: R };

/** Hard cap on rows returned by `listPalettes`, so responses stay bounded. */
export const MAX_LIST = 1000;

/**
 * Every palette method takes the authenticated user's id and scopes its query
 * by it, so a caller can never read or change another user's rows.
 */
export interface Store {
  /** Creates the user on first sign-in, otherwise refreshes their profile. */
  upsertGoogleUser(identity: GoogleIdentity): Promise<UserRow>;
  /** Stores a new session and clears that user's expired ones. */
  createSession(userId: string, tokenHash: string, expiresAt: Date): Promise<void>;
  /** The user owning an unexpired session, or null. */
  findSessionUser(tokenHash: string): Promise<UserRow | null>;
  deleteSession(tokenHash: string): Promise<void>;
  /**
   * Deletes the user; sessions and palettes go with them (ON DELETE CASCADE),
   * and so do their billing event records.
   */
  deleteUser(userId: string): Promise<void>;

  findUserById(userId: string): Promise<UserRow | null>;
  /**
   * Saves what RevenueCat said about the user's purchase as of [checkedAt]
   * (taken just before asking). A slower, older answer never overwrites a
   * newer one. Returns the user as it now stands, or null if they're gone.
   */
  setStoreEntitlement(
    userId: string,
    entitlement: StoreEntitlement,
    checkedAt: Date,
  ): Promise<UserRow | null>;
  /** Logs a webhook delivery; redeliveries of the same event id are ignored. */
  recordBillingEvent(event: BillingEventRow): Promise<void>;

  listPalettes(userId: string): Promise<PaletteRow[]>;
  /**
   * Refuses with "limit" when the user already has [limit] palettes (null: no
   * limit), and "folder_not_found" when folderId isn't one of their folders.
   * The count and insert are serialized per user, so concurrent saves can't
   * slip past the limit.
   */
  createPalette(
    userId: string,
    input: PaletteInput,
    limit: number | null,
  ): Promise<Result<PaletteRow, "limit" | "folder_not_found">>;
  updatePalette(
    userId: string,
    id: string,
    patch: PalettePatch,
  ): Promise<Result<PaletteRow, "not_found" | "folder_not_found">>;
  deletePalette(userId: string, id: string): Promise<boolean>;

  /** Oldest first. */
  listFolders(userId: string): Promise<FolderRow[]>;
  /** Refuses with "duplicate" (same name, any case) or "limit" (at [max] folders). */
  createFolder(
    userId: string,
    name: string,
    max: number,
  ): Promise<Result<FolderRow, "duplicate" | "limit">>;
  renameFolder(
    userId: string,
    id: string,
    name: string,
  ): Promise<Result<FolderRow, "not_found" | "duplicate">>;
  /** Its palettes stay in the library, unfiled. */
  deleteFolder(userId: string, id: string): Promise<boolean>;
}

/** Postgres unique_violation. Drizzle wraps driver errors, so check the cause too. */
function isUniqueViolation(err: unknown): boolean {
  const code = (e: unknown) =>
    typeof e === "object" && e !== null && "code" in e ? (e as { code: unknown }).code : null;
  return code(err) === "23505" || code((err as { cause?: unknown })?.cause) === "23505";
}

export function drizzleStore(db: NodePgDatabase): Store {
  return {
    async upsertGoogleUser(identity) {
      const profile = {
        email: identity.email,
        name: identity.name,
        avatarUrl: identity.picture,
      };
      const [row] = await db
        .insert(users)
        .values({ googleSub: identity.sub, ...profile })
        .onConflictDoUpdate({
          target: users.googleSub,
          set: { ...profile, lastLoginAt: sql`now()` },
        })
        .returning();
      if (!row) throw new Error("upsert returned no row");
      return row;
    },

    async createSession(userId, tokenHash, expiresAt) {
      await db.transaction(async (tx) => {
        await tx
          .delete(sessions)
          .where(and(eq(sessions.userId, userId), lte(sessions.expiresAt, sql`now()`)));
        await tx.insert(sessions).values({ userId, tokenHash, expiresAt });
      });
    },

    async findSessionUser(tokenHash) {
      const [row] = await db
        .select({ user: users })
        .from(sessions)
        .innerJoin(users, eq(users.id, sessions.userId))
        .where(and(eq(sessions.tokenHash, tokenHash), gt(sessions.expiresAt, sql`now()`)))
        .limit(1);
      return row?.user ?? null;
    },

    async deleteSession(tokenHash) {
      await db.delete(sessions).where(eq(sessions.tokenHash, tokenHash));
    },

    async deleteUser(userId) {
      await db.transaction(async (tx) => {
        await tx.delete(billingEvents).where(eq(billingEvents.appUserId, userId));
        await tx.delete(users).where(eq(users.id, userId));
      });
    },

    async findUserById(userId) {
      const [row] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
      return row ?? null;
    },

    async setStoreEntitlement(userId, e, checkedAt) {
      const [row] = await db
        .update(users)
        .set({
          storePlan: e.plan,
          storeProExpiresAt: e.expiresAt,
          storeProductId: e.productId,
          storeWillRenew: e.willRenew,
          storeBillingIssue: e.billingIssue,
          storeSyncedAt: checkedAt,
        })
        .where(
          and(
            eq(users.id, userId),
            or(isNull(users.storeSyncedAt), lte(users.storeSyncedAt, checkedAt)),
          ),
        )
        .returning();
      if (row) return row;
      // Not updated: either the user is gone or a newer answer already landed.
      const [current] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
      return current ?? null;
    },

    async recordBillingEvent(event) {
      await db.insert(billingEvents).values(event).onConflictDoNothing();
    },

    async listPalettes(userId) {
      return db
        .select()
        .from(palettes)
        .where(eq(palettes.userId, userId))
        .orderBy(desc(palettes.createdAt))
        .limit(MAX_LIST);
    },

    async createPalette(userId, input, limit) {
      return db.transaction(async (tx) => {
        // Lock the user's row so their concurrent saves count one at a time.
        await tx.select({ id: users.id }).from(users).where(eq(users.id, userId)).for("update");

        if (limit !== null) {
          const [row] = await tx
            .select({ n: count() })
            .from(palettes)
            .where(eq(palettes.userId, userId));
          if ((row?.n ?? 0) >= limit) return { ok: false, reason: "limit" } as const;
        }

        if (input.folderId && !(await lockOwnFolder(tx, userId, input.folderId))) {
          return { ok: false, reason: "folder_not_found" } as const;
        }

        const [row] = await tx
          .insert(palettes)
          .values({ userId, ...input, folderId: input.folderId ?? null, tags: input.tags ?? [] })
          .returning();
        if (!row) throw new Error("insert returned no row");
        return { ok: true, row } as const;
      });
    },

    async updatePalette(userId, id, patch) {
      return db.transaction(async (tx) => {
        if (patch.folderId && !(await lockOwnFolder(tx, userId, patch.folderId))) {
          return { ok: false, reason: "folder_not_found" } as const;
        }
        const [row] = await tx
          .update(palettes)
          .set({ ...patch, updatedAt: sql`now()` })
          .where(and(eq(palettes.id, id), eq(palettes.userId, userId)))
          .returning();
        return row ? ({ ok: true, row } as const) : ({ ok: false, reason: "not_found" } as const);
      });
    },

    async deletePalette(userId, id) {
      const rows = await db
        .delete(palettes)
        .where(and(eq(palettes.id, id), eq(palettes.userId, userId)))
        .returning({ id: palettes.id });
      return rows.length > 0;
    },

    async listFolders(userId) {
      return db
        .select()
        .from(folders)
        .where(eq(folders.userId, userId))
        .orderBy(asc(folders.createdAt));
    },

    async createFolder(userId, name, max) {
      try {
        return await db.transaction(async (tx) => {
          await tx.select({ id: users.id }).from(users).where(eq(users.id, userId)).for("update");
          const [existing] = await tx
            .select({ n: count() })
            .from(folders)
            .where(eq(folders.userId, userId));
          if ((existing?.n ?? 0) >= max) return { ok: false, reason: "limit" } as const;

          const [row] = await tx.insert(folders).values({ userId, name }).returning();
          if (!row) throw new Error("insert returned no row");
          return { ok: true, row } as const;
        });
      } catch (err) {
        if (isUniqueViolation(err)) return { ok: false, reason: "duplicate" } as const;
        throw err;
      }
    },

    async renameFolder(userId, id, name) {
      try {
        const [row] = await db
          .update(folders)
          .set({ name })
          .where(and(eq(folders.id, id), eq(folders.userId, userId)))
          .returning();
        return row ? ({ ok: true, row } as const) : ({ ok: false, reason: "not_found" } as const);
      } catch (err) {
        if (isUniqueViolation(err)) return { ok: false, reason: "duplicate" } as const;
        throw err;
      }
    },

    async deleteFolder(userId, id) {
      const rows = await db
        .delete(folders)
        .where(and(eq(folders.id, id), eq(folders.userId, userId)))
        .returning({ id: folders.id });
      return rows.length > 0;
    },
  };
}

type Tx = Parameters<Parameters<NodePgDatabase["transaction"]>[0]>[0];

/**
 * True if [folderId] is one of the user's folders. Holds a share lock on it
 * until the transaction ends, so it can't be deleted before the palette
 * pointing at it is written.
 */
async function lockOwnFolder(tx: Tx, userId: string, folderId: string): Promise<boolean> {
  const [row] = await tx
    .select({ id: folders.id })
    .from(folders)
    .where(and(eq(folders.id, folderId), eq(folders.userId, userId)))
    .for("share");
  return row !== undefined;
}
