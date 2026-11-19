import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";

import { SYNC_COOLDOWN_MS, createApp } from "../src/app";
import type { GoogleIdentity, GoogleTokenVerifier } from "../src/auth";
import { NO_ENTITLEMENT, type BillingProvider, type StoreEntitlement } from "../src/billing";
import type { BillingEventRow, FolderRow, PaletteRow, UserRow } from "../src/db/schema";
import { FREE_PALETTE_LIMIT } from "../src/plan";
import type { Store } from "../src/store";
import type { StripeBilling } from "../src/stripe";

type SessionRow = { userId: string; tokenHash: string; expiresAt: Date };

/** In-memory Store with the same ownership, cascade, limit and expiry rules as the SQL one. */
function memoryStore() {
  const users: UserRow[] = [];
  const sessions: SessionRow[] = [];
  const palettes: PaletteRow[] = [];
  const folders: FolderRow[] = [];
  const billingEvents: BillingEventRow[] = [];

  const ownFolder = (userId: string, id: string) =>
    folders.find((f) => f.id === id && f.userId === userId);
  const nameTaken = (userId: string, name: string, exceptId?: string) =>
    folders.some(
      (f) => f.userId === userId && f.id !== exceptId && f.name.toLowerCase() === name.toLowerCase(),
    );

  const store: Store = {
    async upsertGoogleUser(identity) {
      const profile = { email: identity.email, name: identity.name, avatarUrl: identity.picture };
      const existing = users.find((u) => u.googleSub === identity.sub);
      if (existing) {
        Object.assign(existing, profile, { lastLoginAt: new Date() });
        return existing;
      }
      const row: UserRow = {
        id: randomUUID(),
        googleSub: identity.sub,
        ...profile,
        createdAt: new Date(),
        lastLoginAt: new Date(),
        plan: "free",
        proExpiresAt: null,
        storePlan: "free",
        storeProExpiresAt: null,
        storeProductId: null,
        storeWillRenew: false,
        storeBillingIssue: false,
        storeName: null,
        storeManagementUrl: null,
        storeSyncedAt: null,
      };
      users.push(row);
      return row;
    },
    async createSession(userId, tokenHash, expiresAt) {
      sessions.push({ userId, tokenHash, expiresAt });
    },
    async findSessionUser(tokenHash) {
      const s = sessions.find((s) => s.tokenHash === tokenHash && s.expiresAt > new Date());
      return (s && users.find((u) => u.id === s.userId)) ?? null;
    },
    async deleteSession(tokenHash) {
      const i = sessions.findIndex((s) => s.tokenHash === tokenHash);
      if (i !== -1) sessions.splice(i, 1);
    },
    async deleteUser(userId) {
      const drop = <T extends { userId: string }>(rows: T[]) => {
        for (let i = rows.length - 1; i >= 0; i--) if (rows[i]!.userId === userId) rows.splice(i, 1);
      };
      drop(sessions);
      drop(palettes);
      drop(folders);
      for (let i = billingEvents.length - 1; i >= 0; i--) {
        if (billingEvents[i]!.appUserId === userId) billingEvents.splice(i, 1);
      }
      const i = users.findIndex((u) => u.id === userId);
      if (i !== -1) users.splice(i, 1);
    },
    async findUserById(userId) {
      return users.find((u) => u.id === userId) ?? null;
    },
    async setStoreEntitlement(userId, e, checkedAt) {
      const user = users.find((u) => u.id === userId);
      if (!user) return null;
      if (user.storeSyncedAt && user.storeSyncedAt > checkedAt) return user;
      Object.assign(user, {
        storePlan: e.plan,
        storeProExpiresAt: e.expiresAt,
        storeProductId: e.productId,
        storeWillRenew: e.willRenew,
        storeBillingIssue: e.billingIssue,
        storeName: e.store,
        storeManagementUrl: e.managementUrl,
        storeSyncedAt: checkedAt,
      });
      return user;
    },
    async recordBillingEvent(event) {
      if (!billingEvents.some((e) => e.id === event.id)) billingEvents.push(event);
    },
    async listPalettes(userId) {
      return palettes
        .filter((p) => p.userId === userId)
        .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
    },
    async createPalette(userId, input, limit) {
      if (limit !== null && palettes.filter((p) => p.userId === userId).length >= limit) {
        return { ok: false, reason: "limit" };
      }
      if (input.folderId && !ownFolder(userId, input.folderId)) {
        return { ok: false, reason: "folder_not_found" };
      }
      const row: PaletteRow = {
        id: randomUUID(),
        userId,
        createdAt: new Date(),
        updatedAt: new Date(),
        ...input,
        folderId: input.folderId ?? null,
        tags: input.tags ?? [],
      };
      palettes.push(row);
      return { ok: true, row };
    },
    async updatePalette(userId, id, patch) {
      if (patch.folderId && !ownFolder(userId, patch.folderId)) {
        return { ok: false, reason: "folder_not_found" };
      }
      const row = palettes.find((p) => p.id === id && p.userId === userId);
      if (!row) return { ok: false, reason: "not_found" };
      for (const [key, value] of Object.entries(patch)) {
        if (value !== undefined) Object.assign(row, { [key]: value });
      }
      row.updatedAt = new Date();
      return { ok: true, row };
    },
    async deletePalette(userId, id) {
      const i = palettes.findIndex((p) => p.id === id && p.userId === userId);
      if (i === -1) return false;
      palettes.splice(i, 1);
      return true;
    },
    async listFolders(userId) {
      return folders.filter((f) => f.userId === userId);
    },
    async createFolder(userId, name, max) {
      if (folders.filter((f) => f.userId === userId).length >= max) {
        return { ok: false, reason: "limit" };
      }
      if (nameTaken(userId, name)) return { ok: false, reason: "duplicate" };
      const row: FolderRow = { id: randomUUID(), userId, name, createdAt: new Date() };
      folders.push(row);
      return { ok: true, row };
    },
    async renameFolder(userId, id, name) {
      const row = ownFolder(userId, id);
      if (!row) return { ok: false, reason: "not_found" };
      if (nameTaken(userId, name, id)) return { ok: false, reason: "duplicate" };
      row.name = name;
      return { ok: true, row };
    },
    async deleteFolder(userId, id) {
      const i = folders.findIndex((f) => f.id === id && f.userId === userId);
      if (i === -1) return false;
      folders.splice(i, 1);
      // ON DELETE SET NULL
      for (const p of palettes) if (p.folderId === id) p.folderId = null;
      return true;
    },
  };

  return { store, users, sessions, palettes, folders, billingEvents };
}

// Google ID tokens are "google-<name>" in tests.
const verifyGoogleToken: GoogleTokenVerifier = async (idToken) => {
  if (!idToken.startsWith("google-")) return null;
  const who = idToken.slice("google-".length);
  const identity: GoogleIdentity = {
    sub: `sub-${who}`,
    email: `${who}@example.com`,
    name: who,
    picture: null,
  };
  return identity;
};

const samplePalette = {
  name: "Sunset",
  colors: [
    { hex: "#FF5733", name: "Orange Red", textColor: "#000000" },
    { hex: "1a2b3c", name: "Deep Navy", textColor: "FFFFFF" },
  ],
};

let db: ReturnType<typeof memoryStore>;
let app: ReturnType<typeof createApp>;

function call(method: string, path: string, opts: { token?: string; body?: unknown } = {}) {
  const headers: Record<string, string> = {};
  if (opts.token) headers.authorization = `Bearer ${opts.token}`;
  if (opts.body !== undefined) headers["content-type"] = "application/json";
  return app.request(path, {
    method,
    headers,
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
}

async function signIn(who: string): Promise<string> {
  const res = await call("POST", "/v1/auth/google", { body: { idToken: `google-${who}` } });
  expect(res.status).toBe(200);
  return (await res.json()).token;
}

beforeEach(() => {
  db = memoryStore();
  app = createApp({ store: db.store, verifyGoogleToken });
});

describe("sign-in", () => {
  it("health is public", async () => {
    expect((await call("GET", "/health")).status).toBe(200);
  });

  it("rejects an invalid Google token", async () => {
    const res = await call("POST", "/v1/auth/google", { body: { idToken: "forged" } });
    expect(res.status).toBe(401);
    expect(db.users).toHaveLength(0);
  });

  it("creates the user and returns a session", async () => {
    const res = await call("POST", "/v1/auth/google", { body: { idToken: "google-alice" } });
    const body = await res.json();
    expect(body.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(body.user).toMatchObject({ email: "alice@example.com", name: "alice" });
    expect(body.user).not.toHaveProperty("googleSub");
    // Only the hash is stored.
    expect(db.sessions[0]!.tokenHash).not.toBe(body.token);
  });

  it("signing in again reuses the same user", async () => {
    await signIn("alice");
    await signIn("alice");
    expect(db.users).toHaveLength(1);
    expect(db.sessions).toHaveLength(2);
  });
});

describe("sessions", () => {
  it("rejects missing, unknown and expired tokens", async () => {
    expect((await call("GET", "/v1/me")).status).toBe(401);
    expect((await call("GET", "/v1/me", { token: "nope" })).status).toBe(401);

    // Issue a session whose 90-day lifetime ended yesterday.
    const past = () => new Date(Date.now() - 91 * 24 * 60 * 60 * 1000);
    app = createApp({ store: db.store, verifyGoogleToken, now: past });
    const expired = await signIn("alice");
    expect((await call("GET", "/v1/me", { token: expired })).status).toBe(401);
  });

  it("returns the signed-in user", async () => {
    const token = await signIn("alice");
    const res = await call("GET", "/v1/me", { token });
    expect(res.status).toBe(200);
    expect((await res.json()).email).toBe("alice@example.com");
  });

  it("sign-out invalidates only that session", async () => {
    const phone = await signIn("alice");
    const tablet = await signIn("alice");
    expect((await call("DELETE", "/v1/auth/session", { token: phone })).status).toBe(204);
    expect((await call("GET", "/v1/me", { token: phone })).status).toBe(401);
    expect((await call("GET", "/v1/me", { token: tablet })).status).toBe(200);
  });
});

describe("palettes", () => {
  it("creates a palette, normalizing hex values and keeping color order", async () => {
    const token = await signIn("alice");
    const res = await call("POST", "/v1/palettes", { token, body: samplePalette });
    expect(res.status).toBe(201);
    const body = await res.json();
    expect(body.kind).toBe("palette");
    expect(body.colors).toEqual([
      { hex: "ff5733", name: "Orange Red", textColor: "000000" },
      { hex: "1a2b3c", name: "Deep Navy", textColor: "ffffff" },
    ]);
    expect(body).not.toHaveProperty("userId");
  });

  it("rejects invalid input with 400", async () => {
    const token = await signIn("alice");
    const bad = [
      { ...samplePalette, colors: [] },
      { ...samplePalette, name: "   " },
      { ...samplePalette, colors: [{ hex: "zzzzzz", name: "x", textColor: "000000" }] },
      { ...samplePalette, kind: "rainbow" },
    ];
    for (const body of bad) {
      const res = await call("POST", "/v1/palettes", { token, body });
      expect(res.status, JSON.stringify(body)).toBe(400);
    }
    const notJson = await app.request("/v1/palettes", {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: "{nope",
    });
    expect(notJson.status).toBe(400);
  });

  it("lists only the caller's palettes", async () => {
    const alice = await signIn("alice");
    const bob = await signIn("bob");
    await call("POST", "/v1/palettes", { token: alice, body: samplePalette });
    await call("POST", "/v1/palettes", { token: bob, body: { ...samplePalette, name: "Bob's" } });

    const { palettes } = await (await call("GET", "/v1/palettes", { token: alice })).json();
    expect(palettes.map((p: { name: string }) => p.name)).toEqual(["Sunset"]);
  });

  it("renames and deletes own palettes", async () => {
    const token = await signIn("alice");
    const created = await (await call("POST", "/v1/palettes", { token, body: samplePalette })).json();

    const renamed = await call("PATCH", `/v1/palettes/${created.id}`, { token, body: { name: "Dusk" } });
    expect(renamed.status).toBe(200);
    expect((await renamed.json()).name).toBe("Dusk");

    expect((await call("DELETE", `/v1/palettes/${created.id}`, { token })).status).toBe(204);
    expect(db.palettes).toHaveLength(0);
  });

  it("cannot rename or delete another user's palette", async () => {
    const alice = await signIn("alice");
    const bob = await signIn("bob");
    const created = await (await call("POST", "/v1/palettes", { token: alice, body: samplePalette })).json();

    const rename = await call("PATCH", `/v1/palettes/${created.id}`, { token: bob, body: { name: "Mine" } });
    expect(rename.status).toBe(404);
    expect((await call("DELETE", `/v1/palettes/${created.id}`, { token: bob })).status).toBe(404);
    expect(db.palettes[0]!.name).toBe("Sunset");
  });

  it("returns 404 for malformed ids", async () => {
    const token = await signIn("alice");
    expect((await call("DELETE", "/v1/palettes/not-a-uuid", { token })).status).toBe(404);
  });
});

describe("account deletion", () => {
  it("removes the user, their sessions and palettes, and nobody else's", async () => {
    const alice = await signIn("alice");
    const bob = await signIn("bob");
    await call("POST", "/v1/palettes", { token: alice, body: samplePalette });
    await call("POST", "/v1/palettes", { token: bob, body: samplePalette });

    expect((await call("DELETE", "/v1/me", { token: alice })).status).toBe(204);

    expect((await call("GET", "/v1/me", { token: alice })).status).toBe(401);
    expect(db.users.map((u) => u.email)).toEqual(["bob@example.com"]);
    expect(db.palettes).toHaveLength(1);
    expect((await call("GET", "/v1/palettes", { token: bob })).status).toBe(200);
  });
});

// ---------------------------------------------------------------------------
// Pro
// ---------------------------------------------------------------------------

function makePro(who: string, expiresAt: Date | null = null) {
  const user = db.users.find((u) => u.email === `${who}@example.com`)!;
  user.plan = "pro";
  user.proExpiresAt = expiresAt;
}

async function fillLibrary(token: string, n: number) {
  for (let i = 0; i < n; i++) {
    const res = await call("POST", "/v1/palettes", { token, body: { ...samplePalette, name: `P${i}` } });
    expect(res.status).toBe(201);
  }
}

describe("plan", () => {
  it("new accounts are free with a palette limit", async () => {
    const token = await signIn("alice");
    const me = await (await call("GET", "/v1/me", { token })).json();
    expect(me).toMatchObject({
      plan: "free",
      proExpiresAt: null,
      limits: { palettes: FREE_PALETTE_LIMIT },
    });
  });

  it("reports Pro, with its end date, and no limit", async () => {
    const token = await signIn("alice");
    const ends = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
    makePro("alice", ends);
    const me = await (await call("GET", "/v1/me", { token })).json();
    expect(me).toMatchObject({ plan: "pro", proExpiresAt: ends.toISOString(), limits: { palettes: null } });
  });

  it("treats expired Pro as free", async () => {
    const token = await signIn("alice");
    makePro("alice", new Date(Date.now() - 1000));
    const me = await (await call("GET", "/v1/me", { token })).json();
    expect(me).toMatchObject({ plan: "free", proExpiresAt: null });
  });

  it("the sign-in response carries the plan", async () => {
    await signIn("alice");
    makePro("alice");
    const res = await call("POST", "/v1/auth/google", { body: { idToken: "google-alice" } });
    expect((await res.json()).user.plan).toBe("pro");
  });
});

describe("palette limit", () => {
  it("free accounts can't save past the limit until they delete one", async () => {
    const token = await signIn("alice");
    await fillLibrary(token, FREE_PALETTE_LIMIT);

    const full = await call("POST", "/v1/palettes", { token, body: samplePalette });
    expect(full.status).toBe(402);
    expect(await full.json()).toMatchObject({ code: "palette_limit", limit: FREE_PALETTE_LIMIT });
    expect(db.palettes).toHaveLength(FREE_PALETTE_LIMIT);

    const id = db.palettes[0]!.id;
    expect((await call("DELETE", `/v1/palettes/${id}`, { token })).status).toBe(204);
    expect((await call("POST", "/v1/palettes", { token, body: samplePalette })).status).toBe(201);
  });

  it("counts only the caller's palettes", async () => {
    const alice = await signIn("alice");
    const bob = await signIn("bob");
    await fillLibrary(alice, FREE_PALETTE_LIMIT);
    expect((await call("POST", "/v1/palettes", { token: bob, body: samplePalette })).status).toBe(201);
  });

  it("Pro has no limit", async () => {
    const token = await signIn("alice");
    makePro("alice");
    await fillLibrary(token, FREE_PALETTE_LIMIT + 2);
  });

  it("a lapsed Pro account keeps its palettes but can't add more", async () => {
    const token = await signIn("alice");
    makePro("alice");
    await fillLibrary(token, FREE_PALETTE_LIMIT + 2);
    makePro("alice", new Date(Date.now() - 1000));

    const { palettes } = await (await call("GET", "/v1/palettes", { token })).json();
    expect(palettes).toHaveLength(FREE_PALETTE_LIMIT + 2);
    expect((await call("POST", "/v1/palettes", { token, body: samplePalette })).status).toBe(402);
  });
});

describe("folders and tags", () => {
  async function createFolder(token: string, name: string) {
    return call("POST", "/v1/folders", { token, body: { name } });
  }

  it("are Pro-only for free accounts", async () => {
    const token = await signIn("alice");
    const folder = await createFolder(token, "Brand");
    expect(folder.status).toBe(402);
    expect((await folder.json()).code).toBe("pro_required");

    const tagged = await call("POST", "/v1/palettes", { token, body: { ...samplePalette, tags: ["warm"] } });
    expect(tagged.status).toBe(402);

    const created = await (await call("POST", "/v1/palettes", { token, body: samplePalette })).json();
    const tag = await call("PATCH", `/v1/palettes/${created.id}`, { token, body: { tags: ["warm"] } });
    expect(tag.status).toBe(402);
    expect(db.folders).toHaveLength(0);
    expect(db.palettes[0]!.tags).toEqual([]);
  });

  it("Pro can file palettes into folders and tag them", async () => {
    const token = await signIn("alice");
    makePro("alice");
    const folder = await (await createFolder(token, "  Brand  ")).json();
    expect(folder.name).toBe("Brand");

    const res = await call("POST", "/v1/palettes", {
      token,
      body: { ...samplePalette, folderId: folder.id, tags: [" warm ", "Warm", "sunset   glow"] },
    });
    expect(res.status).toBe(201);
    const palette = await res.json();
    expect(palette).toMatchObject({ folderId: folder.id, tags: ["warm", "sunset glow"] });

    const moved = await call("PATCH", `/v1/palettes/${palette.id}`, {
      token,
      body: { folderId: null, tags: ["cool"], name: "Dusk" },
    });
    expect(await moved.json()).toMatchObject({ folderId: null, tags: ["cool"], name: "Dusk" });

    const { folders } = await (await call("GET", "/v1/folders", { token })).json();
    expect(folders.map((f: { name: string }) => f.name)).toEqual(["Brand"]);
  });

  it("folder names are unique per user, ignoring case", async () => {
    const alice = await signIn("alice");
    const bob = await signIn("bob");
    makePro("alice");
    makePro("bob");
    expect((await createFolder(alice, "Brand")).status).toBe(201);
    expect((await createFolder(alice, "brand")).status).toBe(409);
    expect((await createFolder(bob, "Brand")).status).toBe(201);

    const other = await (await createFolder(alice, "Web")).json();
    const rename = await call("PATCH", `/v1/folders/${other.id}`, { token: alice, body: { name: "BRAND" } });
    expect(rename.status).toBe(409);
  });

  it("can't use or change another user's folder", async () => {
    const alice = await signIn("alice");
    const bob = await signIn("bob");
    makePro("alice");
    makePro("bob");
    const folder = await (await createFolder(alice, "Brand")).json();

    const file = await call("POST", "/v1/palettes", { token: bob, body: { ...samplePalette, folderId: folder.id } });
    expect(file.status).toBe(404);
    const rename = await call("PATCH", `/v1/folders/${folder.id}`, { token: bob, body: { name: "Mine" } });
    expect(rename.status).toBe(404);
    expect((await call("DELETE", `/v1/folders/${folder.id}`, { token: bob })).status).toBe(404);
    const { folders } = await (await call("GET", "/v1/folders", { token: bob })).json();
    expect(folders).toEqual([]);
  });

  it("deleting a folder keeps its palettes, unfiled", async () => {
    const token = await signIn("alice");
    makePro("alice");
    const folder = await (await createFolder(token, "Brand")).json();
    await call("POST", "/v1/palettes", { token, body: { ...samplePalette, folderId: folder.id } });

    expect((await call("DELETE", `/v1/folders/${folder.id}`, { token })).status).toBe(204);
    const { palettes } = await (await call("GET", "/v1/palettes", { token })).json();
    expect(palettes).toHaveLength(1);
    expect(palettes[0].folderId).toBeNull();
  });

  it("after Pro lapses, folders and tags can still be removed", async () => {
    const token = await signIn("alice");
    makePro("alice");
    const folder = await (await createFolder(token, "Brand")).json();
    const palette = await (
      await call("POST", "/v1/palettes", {
        token,
        body: { ...samplePalette, folderId: folder.id, tags: ["warm"] },
      })
    ).json();
    makePro("alice", new Date(Date.now() - 1000));

    const cleared = await call("PATCH", `/v1/palettes/${palette.id}`, {
      token,
      body: { folderId: null, tags: [] },
    });
    expect(cleared.status).toBe(200);
    expect((await call("DELETE", `/v1/folders/${folder.id}`, { token })).status).toBe(204);
    expect((await createFolder(token, "Again")).status).toBe(402);
  });

  it("rejects bad updates", async () => {
    const token = await signIn("alice");
    makePro("alice");
    const palette = await (await call("POST", "/v1/palettes", { token, body: samplePalette })).json();
    const eleven = Array.from({ length: 11 }, (_, i) => `t${i}`);
    const bad = [{}, { folderId: "nope" }, { tags: ["x".repeat(31)] }, { tags: eleven }];
    for (const body of bad) {
      const res = await call("PATCH", `/v1/palettes/${palette.id}`, { token, body });
      expect(res.status, JSON.stringify(body)).toBe(400);
    }
    expect((await createFolder(token, " ")).status).toBe(400);
  });

  it("account deletion removes folders too", async () => {
    const token = await signIn("alice");
    makePro("alice");
    await createFolder(token, "Brand");
    await call("DELETE", "/v1/me", { token });
    expect(db.folders).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// Billing
// ---------------------------------------------------------------------------

const WEBHOOK_SECRET = "w".repeat(40);
const DAY = 24 * 60 * 60 * 1000;

/** RevenueCat stand-in: what each customer owns, and who was asked about. */
function fakeRevenueCat() {
  const owned = new Map<string, StoreEntitlement>();
  const fetched: string[] = [];
  const testers: string[] = [];
  const deleted: string[] = [];
  let down = false;
  const provider: BillingProvider = {
    async getEntitlement(id, _now, context) {
      if (down) throw new Error("RevenueCat is down");
      fetched.push(id);
      if (context?.tester) testers.push(id);
      return owned.get(id) ?? NO_ENTITLEMENT;
    },
    async deleteCustomer(id) {
      deleted.push(id);
    },
  };
  return {
    provider,
    owned,
    fetched,
    testers,
    deleted,
    setDown: (v: boolean) => (down = v),
  };
}

const weekly = (endsInMs = 7 * DAY): StoreEntitlement => ({
  plan: "pro",
  expiresAt: new Date(Date.now() + endsInMs),
  productId: "pro:weekly",
  willRenew: true,
  billingIssue: false,
  store: "play_store",
  managementUrl: "https://play.google.com/store/account/subscriptions",
});

describe("billing", () => {
  let rc: ReturnType<typeof fakeRevenueCat>;
  let clock: number;

  beforeEach(() => {
    rc = fakeRevenueCat();
    clock = Date.now();
    app = createApp({
      store: db.store,
      verifyGoogleToken,
      billing: {
        provider: rc.provider,
        webhookSecret: WEBHOOK_SECRET,
        testerEmails: new Set(["tester@example.com"]),
      },
      now: () => new Date(clock),
    });
  });

  const userId = (who: string) => db.users.find((u) => u.email === `${who}@example.com`)!.id;

  function webhook(event: Record<string, unknown>, auth = `Bearer ${WEBHOOK_SECRET}`) {
    return app.request("/v1/billing/revenuecat", {
      method: "POST",
      headers: { authorization: auth, "content-type": "application/json" },
      body: JSON.stringify({ api_version: "1.0", event }),
    });
  }

  const me = async (token: string) => (await call("GET", "/v1/me", { token })).json();

  it("sync grants Pro only when RevenueCat says the user owns it", async () => {
    const token = await signIn("alice");
    let body = await (await call("POST", "/v1/billing/sync", { token })).json();
    expect(body).toMatchObject({ plan: "free", subscription: null });

    rc.owned.set(userId("alice"), weekly());
    clock += SYNC_COOLDOWN_MS;
    body = await (await call("POST", "/v1/billing/sync", { token })).json();
    expect(body).toMatchObject({
      plan: "pro",
      limits: { palettes: null },
      subscription: {
        productId: "pro:weekly",
        willRenew: true,
        billingIssue: false,
        store: "play_store",
        managementUrl: "https://play.google.com/store/account/subscriptions",
      },
    });
    expect(body.proExpiresAt).toBe(body.subscription.expiresAt);
  });

  it("sync ignores anything the app sends", async () => {
    const token = await signIn("alice");
    const res = await call("POST", "/v1/billing/sync", {
      token,
      body: { plan: "pro", entitlement: "pro", purchaseToken: "fake" },
    });
    expect((await res.json()).plan).toBe("free");
  });

  it("sync is rate limited per user", async () => {
    const token = await signIn("alice");
    await call("POST", "/v1/billing/sync", { token });
    await call("POST", "/v1/billing/sync", { token });
    expect(rc.fetched).toHaveLength(1);
    clock += SYNC_COOLDOWN_MS;
    await call("POST", "/v1/billing/sync", { token });
    expect(rc.fetched).toHaveLength(2);
  });

  it("marks only listed tester accounts as testers", async () => {
    const tester = await signIn("tester");
    const alice = await signIn("alice");
    await call("POST", "/v1/billing/sync", { token: tester });
    await call("POST", "/v1/billing/sync", { token: alice });
    expect(rc.testers).toEqual([userId("tester")]);
  });

  it("sync needs a session", async () => {
    expect((await call("POST", "/v1/billing/sync")).status).toBe(401);
  });

  it("a RevenueCat outage fails the sync instead of removing Pro", async () => {
    const token = await signIn("alice");
    rc.owned.set(userId("alice"), weekly());
    await call("POST", "/v1/billing/sync", { token });
    rc.setDown(true);
    clock += SYNC_COOLDOWN_MS;
    expect((await call("POST", "/v1/billing/sync", { token })).status).toBe(500);
    expect((await me(token)).plan).toBe("pro");
  });

  it("rejects webhooks without the shared secret", async () => {
    await signIn("alice");
    rc.owned.set(userId("alice"), weekly());
    const event = { id: "e1", type: "INITIAL_PURCHASE", app_user_id: userId("alice") };
    expect((await webhook(event, "Bearer wrong")).status).toBe(401);
    expect((await webhook(event, WEBHOOK_SECRET)).status).toBe(401);
    expect((await webhook(event, "")).status).toBe(401);
    expect(rc.fetched).toHaveLength(0);
    expect(db.billingEvents).toHaveLength(0);
  });

  it("a webhook re-reads the customer instead of trusting the payload", async () => {
    const token = await signIn("alice");
    // Claims a purchase RevenueCat doesn't know about: nothing is granted.
    const forged = {
      id: "e1",
      type: "INITIAL_PURCHASE",
      app_user_id: userId("alice"),
      entitlement_ids: ["pro"],
      expiration_at_ms: Date.now() + 365 * DAY,
    };
    expect((await webhook(forged)).status).toBe(200);
    expect((await me(token)).plan).toBe("free");

    rc.owned.set(userId("alice"), weekly());
    clock += 1;
    await webhook({ id: "e2", type: "RENEWAL", app_user_id: userId("alice") });
    expect((await me(token)).plan).toBe("pro");

    // Expiry or refund: RevenueCat no longer has an active entitlement.
    rc.owned.set(userId("alice"), { ...weekly(-1000), plan: "free", willRenew: false });
    clock += 1;
    await webhook({ id: "e3", type: "EXPIRATION", app_user_id: userId("alice") });
    expect(await me(token)).toMatchObject({ plan: "free", subscription: null });

    // Redelivery is logged once.
    await webhook({ id: "e3", type: "EXPIRATION", app_user_id: userId("alice") });
    expect(db.billingEvents.map((e) => e.id)).toEqual(["e1", "e2", "e3"]);
  });

  it("a transfer updates both accounts", async () => {
    const alice = await signIn("alice");
    const bob = await signIn("bob");
    rc.owned.set(userId("alice"), weekly());
    await webhook({ id: "e1", type: "INITIAL_PURCHASE", app_user_id: userId("alice") });

    rc.owned.delete(userId("alice"));
    rc.owned.set(userId("bob"), weekly());
    clock += 1;
    await webhook({
      id: "e2",
      type: "TRANSFER",
      transferred_from: [userId("alice")],
      transferred_to: [userId("bob")],
    });
    expect((await me(alice)).plan).toBe("free");
    expect((await me(bob)).plan).toBe("pro");
  });

  it("ignores ids that aren't our users", async () => {
    const res = await webhook({
      id: "e1",
      type: "TEST",
      app_user_id: "$RCAnonymousID:abc",
      aliases: [randomUUID()],
    });
    expect(res.status).toBe(200);
    expect(rc.fetched).toHaveLength(0);
  });

  it("an older RevenueCat answer can't overwrite a newer one", async () => {
    await signIn("alice");
    const id = userId("alice");
    await db.store.setStoreEntitlement(id, weekly(), new Date(clock));
    await db.store.setStoreEntitlement(id, NO_ENTITLEMENT, new Date(clock - 5000));
    expect(db.users[0]!.storePlan).toBe("pro");
  });

  it("a support grant survives a store sync that finds nothing", async () => {
    const token = await signIn("alice");
    makePro("alice");
    const body = await (await call("POST", "/v1/billing/sync", { token })).json();
    expect(body).toMatchObject({ plan: "pro", proExpiresAt: null, subscription: null });
  });

  it("reports the later end when both a grant and a purchase are active", async () => {
    const token = await signIn("alice");
    makePro("alice", new Date(Date.now() + 30 * DAY));
    rc.owned.set(userId("alice"), weekly(7 * DAY));
    const body = await (await call("POST", "/v1/billing/sync", { token })).json();
    expect(new Date(body.proExpiresAt).getTime()).toBeGreaterThan(Date.now() + 29 * DAY);
  });

  it("account deletion also deletes the RevenueCat customer and billing log", async () => {
    const token = await signIn("alice");
    const id = userId("alice");
    await webhook({ id: "e1", type: "INITIAL_PURCHASE", app_user_id: id });
    expect((await call("DELETE", "/v1/me", { token })).status).toBe(204);
    expect(rc.deleted).toEqual([id]);
    expect(db.billingEvents).toHaveLength(0);
  });

  it("billing routes 503 when RevenueCat isn't configured", async () => {
    app = createApp({ store: db.store, verifyGoogleToken });
    const token = await signIn("alice");
    expect((await call("POST", "/v1/billing/sync", { token })).status).toBe(503);
    expect((await webhook({ id: "e1", type: "TEST" })).status).toBe(503);
  });
});

/** Stripe stand-in: one mode's checkouts, sessions and receipts posted to RevenueCat. */
function fakeStripe(mode: "live" | "test") {
  const created: { plan: string; userId: string; email: string; successUrl: string; cancelUrl: string }[] = [];
  const reported: [string, string][] = [];
  const sessions = new Map<string, { userId: string; status: string; subscriptionId: string | null }>();
  const billing: StripeBilling = {
    async plans() {
      return [
        { id: "monthly", amount: 499, currency: "usd", interval: "month" },
        { id: "yearly", amount: 3599, currency: "usd", interval: "year" },
      ];
    },
    async createCheckout(input) {
      created.push(input);
      return `https://checkout.stripe.com/c/pay/cs_${mode}_1`;
    },
    async getCheckout(id) {
      const s = sessions.get(id);
      return s ?? { userId: null, status: null, subscriptionId: null };
    },
    async reportToRevenueCat(userId, subscriptionId) {
      reported.push([userId, subscriptionId]);
    },
    async portalUrl(userId) {
      return [...sessions.values()].some((s) => s.userId === userId) ? "https://billing.stripe.com/p/session/x" : null;
    },
  };
  return { billing, created, reported, sessions };
}

describe("web checkout (Stripe)", () => {
  const WEB = "https://color-blendr-ui.vercel.app";
  let rc: ReturnType<typeof fakeRevenueCat>;
  let live: ReturnType<typeof fakeStripe>;
  let test: ReturnType<typeof fakeStripe>;
  let clock: number;

  beforeEach(() => {
    rc = fakeRevenueCat();
    live = fakeStripe("live");
    test = fakeStripe("test");
    clock = Date.now();
    app = createApp({
      store: db.store,
      verifyGoogleToken,
      billing: { provider: rc.provider, webhookSecret: WEBHOOK_SECRET, testerEmails: new Set(["tester@example.com"]) },
      webOrigins: new Set([WEB]),
      stripe: { live: live.billing, test: test.billing },
      now: () => new Date(clock),
    });
  });

  const userId = (who: string) => db.users.find((u) => u.email === `${who}@example.com`)!.id;

  function post(path: string, token: string, body?: unknown, origin = WEB) {
    return app.request(path, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json", origin },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  }

  it("lists the plans, and nothing when Stripe isn't set up", async () => {
    const token = await signIn("alice");
    const res = await call("GET", "/v1/billing/plans", { token });
    expect((await res.json()).plans.map((p: { id: string }) => p.id)).toEqual(["monthly", "yearly"]);

    app = createApp({
      store: db.store,
      verifyGoogleToken,
      billing: { provider: rc.provider, webhookSecret: WEBHOOK_SECRET },
    });
    expect(await (await call("GET", "/v1/billing/plans", { token })).json()).toEqual({ plans: [], test: false });
  });

  it("starts a checkout tied to the signed-in account, returning to the web app", async () => {
    const token = await signIn("alice");
    const res = await post("/v1/billing/checkout", token, { plan: "yearly" });
    expect(res.status).toBe(200);
    expect((await res.json()).url).toMatch(/^https:\/\/checkout\.stripe\.com\//);
    expect(live.created).toEqual([
      {
        plan: "yearly",
        userId: userId("alice"),
        email: "alice@example.com",
        successUrl: `${WEB}/app/account?checkout=success&session_id={CHECKOUT_SESSION_ID}`,
        cancelUrl: `${WEB}/app/?checkout=cancelled`,
      },
    ]);
  });

  it("refuses unknown plans, unknown origins and accounts that already have Pro", async () => {
    const token = await signIn("alice");
    expect((await post("/v1/billing/checkout", token, { plan: "lifetime" })).status).toBe(400);
    expect((await post("/v1/billing/checkout", token, { plan: "monthly" }, "https://evil.example")).status).toBe(400);
    rc.owned.set(userId("alice"), weekly());
    await call("POST", "/v1/billing/sync", { token });
    const res = await post("/v1/billing/checkout", token, { plan: "monthly" });
    expect(res.status).toBe(409);
    expect((await res.json()).code).toBe("already_pro");
    expect(live.created).toHaveLength(0);
  });

  it("test mode is for tester accounts only", async () => {
    const alice = await signIn("alice");
    const tester = await signIn("tester");
    expect((await post("/v1/billing/checkout", alice, { plan: "monthly", test: true })).status).toBe(403);
    expect((await call("GET", "/v1/billing/plans?test=1", { token: alice })).status).toBe(403);
    expect((await post("/v1/billing/checkout", tester, { plan: "monthly", test: true })).status).toBe(200);
    expect(test.created).toHaveLength(1);
    expect(live.created).toHaveLength(0);
  });

  it("after checkout, reports the account's own paid session to RevenueCat, then reads Pro from RevenueCat", async () => {
    const token = await signIn("alice");
    live.sessions.set("cs_live_1", { userId: userId("alice"), status: "complete", subscriptionId: "sub_1" });
    rc.owned.set(userId("alice"), { ...weekly(), store: "stripe", productId: "prod_yearly" });
    const body = await (await post("/v1/billing/sync", token, { checkoutSessionId: "cs_live_1" })).json();
    expect(live.reported).toEqual([[userId("alice"), "sub_1"]]);
    expect(body).toMatchObject({ plan: "pro", subscription: { store: "stripe" } });
  });

  it("won't report someone else's or an unpaid checkout", async () => {
    const alice = await signIn("alice");
    await signIn("bob");
    live.sessions.set("cs_live_bob", { userId: userId("bob"), status: "complete", subscriptionId: "sub_b" });
    live.sessions.set("cs_live_open", { userId: userId("alice"), status: "open", subscriptionId: null });
    expect((await post("/v1/billing/sync", alice, { checkoutSessionId: "cs_live_bob" })).status).toBe(404);
    clock += SYNC_COOLDOWN_MS;
    expect((await post("/v1/billing/sync", alice, { checkoutSessionId: "cs_live_open" })).status).toBe(200);
    expect((await post("/v1/billing/sync", alice, { checkoutSessionId: "not-a-session" })).status).toBe(400);
    expect(live.reported).toHaveLength(0);
  });

  it("opens the Stripe customer portal only for an account with a web subscription", async () => {
    const alice = await signIn("alice");
    expect((await post("/v1/billing/portal", alice)).status).toBe(404);
    live.sessions.set("cs_live_1", { userId: userId("alice"), status: "complete", subscriptionId: "sub_1" });
    const res = await post("/v1/billing/portal", alice);
    expect((await res.json()).url).toMatch(/^https:\/\/billing\.stripe\.com\//);
  });
});

describe("CORS for the web app", () => {
  const WEB = "https://color-blendr-ui.vercel.app";

  beforeEach(() => {
    app = createApp({ store: db.store, verifyGoogleToken, webOrigins: new Set([WEB]) });
  });

  it("answers preflights from allowed origins only", async () => {
    const preflight = (origin: string) =>
      app.request("/v1/palettes", {
        method: "OPTIONS",
        headers: {
          origin,
          "access-control-request-method": "POST",
          "access-control-request-headers": "authorization, content-type",
        },
      });
    const ok = await preflight(WEB);
    expect(ok.status).toBe(204);
    expect(ok.headers.get("access-control-allow-origin")).toBe(WEB);
    expect(ok.headers.get("access-control-allow-headers")).toContain("authorization");
    expect(ok.headers.get("access-control-allow-credentials")).toBeNull();

    const evil = await preflight("https://evil.example");
    expect(evil.headers.get("access-control-allow-origin")).toBeNull();
  });

  it("adds the header to normal and error responses", async () => {
    const token = await signIn("alice");
    const me = await app.request("/v1/me", {
      headers: { origin: WEB, authorization: `Bearer ${token}` },
    });
    expect(me.status).toBe(200);
    expect(me.headers.get("access-control-allow-origin")).toBe(WEB);

    const unauthorized = await app.request("/v1/me", { headers: { origin: WEB } });
    expect(unauthorized.status).toBe(401);
    expect(unauthorized.headers.get("access-control-allow-origin")).toBe(WEB);

    const bad = await app.request("/v1/palettes", {
      method: "POST",
      headers: { origin: WEB, authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: "{",
    });
    expect(bad.status).toBe(400);
    expect(bad.headers.get("access-control-allow-origin")).toBe(WEB);
  });

  it("is off by default and never on the RevenueCat webhook", async () => {
    app = createApp({ store: db.store, verifyGoogleToken });
    const res = await app.request("/v1/me", { headers: { origin: WEB } });
    expect(res.headers.get("access-control-allow-origin")).toBeNull();

    app = createApp({ store: db.store, verifyGoogleToken, webOrigins: new Set([WEB]) });
    const hook = await app.request("/v1/billing/revenuecat", {
      method: "OPTIONS",
      headers: { origin: WEB, "access-control-request-method": "POST" },
    });
    expect(hook.headers.get("access-control-allow-origin")).toBeNull();
  });
});
