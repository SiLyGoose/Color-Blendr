// Read-only: every account's plan columns (no emails) and the last 10 billing
// events. Run from api/:  node --env-file=.env.local scripts/plan-state.mjs
// Needs DATABASE_URL (in .env.local).
import { createRequire } from "node:module";

const require = createRequire(process.cwd() + "/package.json");
const { Client } = require("pg");

const client = new Client({ connectionString: process.env.DB_URL ?? process.env.DATABASE_URL });
await client.connect();
await client.query("set default_transaction_read_only = on");
const users = await client.query(
  `select id, plan, pro_expires_at, store_plan, store_pro_expires_at, store_product_id,
          store_will_renew, store_billing_issue, store_name, store_synced_at
     from users order by created_at`,
);
for (const u of users.rows) console.log(JSON.stringify(u));
const events = await client.query(
  "select type, environment, app_user_id, received_at from billing_events order by received_at desc limit 10",
);
console.log("billing events:");
for (const e of events.rows) console.log(JSON.stringify(e));
await client.end();
