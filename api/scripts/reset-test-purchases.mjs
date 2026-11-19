// Undoes test purchases on ONE account: deletes its RevenueCat customer, checks
// RevenueCat reports no entitlement, then resets the account's store_* columns.
// Leaves the hand-granted plan (plan / pro_expires_at) alone.
// Run from api/:  node --env-file=.env.local scripts/reset-test-purchases.mjs <user id>
// Needs REVENUECAT_SECRET_KEY and DATABASE_URL (both in .env.local). Prints no secrets.
// RevenueCat's GET can lag a few seconds after the delete; if it refuses, re-run.
import { createRequire } from "node:module";

const require = createRequire(process.cwd() + "/package.json");
const { Client } = require("pg");

const userId = process.argv[2];
if (!/^[0-9a-f-]{36}$/.test(userId ?? "")) throw new Error("pass a user id");
const rc = (method, path) =>
  fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}${path}`, {
    method,
    headers: { authorization: `Bearer ${process.env.REVENUECAT_SECRET_KEY}` },
  });

const del = await rc("DELETE", "");
console.log("RevenueCat delete customer:", del.status);
if (!del.ok && del.status !== 404) throw new Error(await del.text());

// GET recreates an empty customer, which is harmless (see docs/monetization.md §5).
const get = await rc("GET", "");
const body = await get.json();
const ents = body.subscriber?.entitlements ?? {};
const subs = body.subscriber?.subscriptions ?? {};
console.log("RevenueCat now: entitlements", JSON.stringify(Object.keys(ents)), "subscriptions", JSON.stringify(Object.keys(subs)));
if (Object.keys(ents).length > 0) throw new Error("RevenueCat still reports an entitlement; not touching the database");

const client = new Client({ connectionString: process.env.DB_URL ?? process.env.DATABASE_URL });
await client.connect();
const res = await client.query(
  `update users set store_plan = 'free', store_pro_expires_at = null, store_product_id = null,
          store_will_renew = false, store_billing_issue = false, store_synced_at = now()
    where id = $1
    returning plan, store_plan, store_product_id, store_will_renew`,
  [userId],
);
console.log("database:", JSON.stringify(res.rows[0]));
await client.end();
