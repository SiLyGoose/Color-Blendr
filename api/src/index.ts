import { attachDatabasePool } from "@neon/functions";
import { drizzle } from "drizzle-orm/node-postgres";
import { Pool } from "pg";

import { createApp, type BillingDeps } from "./app";
import { googleIdTokenVerifier } from "./auth";
import { revenueCatProvider } from "./billing";
import { stripeBilling, stripeConfigFromEnv, type StripeBilling, type StripeMode } from "./stripe";
import { drizzleStore } from "./store";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error("DATABASE_URL is required");

const googleClientId = process.env.GOOGLE_CLIENT_ID;
if (!googleClientId) throw new Error("GOOGLE_CLIENT_ID is required");

// One small pool per isolate, reused across requests.
const pool = new Pool({ connectionString: databaseUrl, max: 5 });
attachDatabasePool(pool);

const list = (s: string) =>
  s
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);

/**
 * Purchases need both RevenueCat secrets (set in .env.local, never in the app
 * or in git). Without them the API runs as before and billing routes 503.
 */
function billingFromEnv(env: NodeJS.ProcessEnv): BillingDeps | undefined {
  const secretKey = env.REVENUECAT_SECRET_KEY;
  const webhookSecret = env.REVENUECAT_WEBHOOK_SECRET;
  if (!secretKey || !webhookSecret) {
    console.warn("RevenueCat secrets not set: purchases are disabled");
    return undefined;
  }
  if (!secretKey.startsWith("sk_")) {
    throw new Error("REVENUECAT_SECRET_KEY must be a secret key (sk_...), not the app's public key");
  }
  if (webhookSecret.length < 32) {
    throw new Error("REVENUECAT_WEBHOOK_SECRET must be at least 32 characters");
  }
  const testerEmails = new Set(
    (env.REVENUECAT_TESTER_EMAILS ?? "")
      .split(",")
      .map((e) => e.trim().toLowerCase())
      .filter(Boolean),
  );
  return {
    webhookSecret,
    testerEmails,
    provider: revenueCatProvider({
      secretKey,
      entitlementId: env.REVENUECAT_ENTITLEMENT_ID || "pro",
      sandboxStores: list(env.REVENUECAT_SANDBOX_STORES ?? "play_store"),
      allowedStores: list(env.REVENUECAT_ALLOWED_STORES || "play_store,stripe,rc_billing,promotional"),
    }),
  };
}

/** WEB_ORIGINS: comma-separated origins of the web app (see neon.ts). */
const webOrigins = new Set(
  (process.env.WEB_ORIGINS ?? "")
    .split(",")
    .map((o) => o.trim().replace(/\/+$/, ""))
    .filter(Boolean),
);

/** Stripe Checkout for the web app, per mode that has its keys and prices set. */
const stripe: Partial<Record<StripeMode, StripeBilling>> = {};
for (const mode of ["live", "test"] as const) {
  const cfg = stripeConfigFromEnv(process.env, mode);
  if (cfg) stripe[mode] = stripeBilling(cfg);
}

export default createApp({
  store: drizzleStore(drizzle(pool)),
  verifyGoogleToken: googleIdTokenVerifier(googleClientId),
  billing: billingFromEnv(process.env),
  webOrigins,
  stripe,
});
