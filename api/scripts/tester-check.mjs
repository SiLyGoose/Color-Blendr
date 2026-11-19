// Read-only: whether each account's email is in REVENUECAT_TESTER_EMAILS
// (prints no emails). Run from api/:  node --env-file=.env.local scripts/tester-check.mjs
// Needs DATABASE_URL and REVENUECAT_TESTER_EMAILS (both in .env.local).
import { createRequire } from "node:module";

const require = createRequire(process.cwd() + "/package.json");
const { Client } = require("pg");

const testers = new Set(
  (process.env.REVENUECAT_TESTER_EMAILS ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean),
);
const client = new Client({ connectionString: process.env.DB_URL ?? process.env.DATABASE_URL });
await client.connect();
await client.query("set default_transaction_read_only = on");
const { rows } = await client.query("select email from users order by created_at");
console.log(`tester list has ${testers.size} address(es)`);
rows.forEach((r, i) => console.log(`account ${i + 1}: ${testers.has(r.email.toLowerCase()) ? "on" : "NOT on"} the tester list`));
await client.end();
