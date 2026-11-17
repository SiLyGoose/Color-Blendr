// Runs the real Drizzle store against Postgres. Skipped unless
// SMOKE_DATABASE_URL points at a disposable, fully migrated database (e.g. a
// schema-only Neon branch). It creates and deletes its own users.
import { randomUUID } from "node:crypto";
import { drizzle } from "drizzle-orm/node-postgres";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { drizzleStore } from "../src/store";

const url = process.env.SMOKE_DATABASE_URL;

describe.skipIf(!url)("drizzle store (SQL)", () => {
  const pool = new Pool({ connectionString: url, max: 10 });
  const store = drizzleStore(drizzle(pool));
  const created: string[] = [];

  async function newUser() {
    const user = await store.upsertGoogleUser({
      sub: `smoke-${randomUUID()}`,
      email: "smoke@example.com",
      name: null,
      picture: null,
    });
    created.push(user.id);
    return user;
  }

  const palette = {
    name: "Smoke",
    kind: "palette" as const,
    colors: [{ hex: "ff5733", name: "Orange", textColor: "000000" }],
  };

  afterAll(async () => {
    for (const id of created) await store.deleteUser(id);
    await pool.end();
  });

  it("new users are free", async () => {
    const user = await newUser();
    expect(user.plan).toBe("free");
    expect(user.proExpiresAt).toBeNull();
  });

  it("concurrent saves can't pass the limit", async () => {
    const user = await newUser();
    const results = await Promise.all(
      Array.from({ length: 8 }, () => store.createPalette(user.id, palette, 3)),
    );
    expect(results.filter((r) => r.ok)).toHaveLength(3);
    expect(results.filter((r) => !r.ok && r.reason === "limit")).toHaveLength(5);
    expect(await store.listPalettes(user.id)).toHaveLength(3);
  });

  it("folders: ownership, case-insensitive names, unfiling on delete", async () => {
    const alice = await newUser();
    const bob = await newUser();

    const brand = await store.createFolder(alice.id, "Brand", 100);
    expect(brand.ok).toBe(true);
    if (!brand.ok) return;
    expect(await store.createFolder(alice.id, "BRAND", 100)).toEqual({ ok: false, reason: "duplicate" });
    expect((await store.createFolder(bob.id, "Brand", 100)).ok).toBe(true);

    const web = await store.createFolder(alice.id, "Web", 100);
    if (!web.ok) throw new Error("create failed");
    expect(await store.renameFolder(alice.id, web.row.id, "brand")).toEqual({
      ok: false,
      reason: "duplicate",
    });
    expect(await store.renameFolder(bob.id, web.row.id, "Mine")).toEqual({
      ok: false,
      reason: "not_found",
    });

    // Bob can't file into Alice's folder.
    expect(await store.createPalette(bob.id, { ...palette, folderId: brand.row.id }, null)).toEqual({
      ok: false,
      reason: "folder_not_found",
    });

    const filed = await store.createPalette(
      alice.id,
      { ...palette, folderId: brand.row.id, tags: ["warm", "sunset glow"] },
      null,
    );
    if (!filed.ok) throw new Error("create failed");
    expect(filed.row.tags).toEqual(["warm", "sunset glow"]);

    const moved = await store.updatePalette(alice.id, filed.row.id, { folderId: web.row.id, tags: [] });
    expect(moved.ok && moved.row.folderId).toBe(web.row.id);
    expect(moved.ok && moved.row.tags).toEqual([]);

    expect(await store.deleteFolder(bob.id, web.row.id)).toBe(false);
    expect(await store.deleteFolder(alice.id, web.row.id)).toBe(true);
    const [after] = await store.listPalettes(alice.id);
    expect(after?.folderId).toBeNull();

    expect((await store.listFolders(alice.id)).map((f) => f.name)).toEqual(["Brand"]);
  });

  it("folder limit", async () => {
    const user = await newUser();
    expect((await store.createFolder(user.id, "A", 2)).ok).toBe(true);
    expect((await store.createFolder(user.id, "B", 2)).ok).toBe(true);
    expect(await store.createFolder(user.id, "C", 2)).toEqual({ ok: false, reason: "limit" });
  });

  it("deleting the user removes their folders", async () => {
    const user = await newUser();
    await store.createFolder(user.id, "Gone", 100);
    await store.deleteUser(user.id);
    expect(await store.listFolders(user.id)).toEqual([]);
  });

  it("store entitlement: newer answers win, deletion clears the billing log", async () => {
    const user = await newUser();
    const t = new Date();
    const pro = {
      plan: "pro" as const,
      expiresAt: new Date(t.getTime() + 7 * 864e5),
      productId: "pro:weekly",
      willRenew: true,
      billingIssue: false,
      store: "rc_billing",
      managementUrl: "https://pay.rev.cat/manage/abc",
    };
    expect((await store.setStoreEntitlement(user.id, pro, t))?.storePlan).toBe("pro");
    const stale = await store.setStoreEntitlement(
      user.id,
      { ...pro, plan: "free" },
      new Date(t.getTime() - 1000),
    );
    expect(stale?.storePlan).toBe("pro");

    const eventId = `smoke-${randomUUID()}`;
    await store.recordBillingEvent({ id: eventId, type: "TEST", appUserId: user.id });
    await store.recordBillingEvent({ id: eventId, type: "TEST", appUserId: user.id });
    await store.deleteUser(user.id);
    expect(await store.findUserById(user.id)).toBeNull();
    expect(await store.setStoreEntitlement(user.id, pro, new Date())).toBeNull();
  });
});
