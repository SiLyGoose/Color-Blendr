import { defineConfig } from "@neon/config/v1";

export default defineConfig({
  functions: {
    api: {
      name: "Color Blendr API",
      source: "src/index.ts",
      env: {
        // Not a secret: the OAuth *web* client ID (Google Cloud project
        // 381822964866) that the app passes to Google Sign-In as serverClientId.
        // Google ID tokens must carry it as their audience.
        GOOGLE_CLIENT_ID:
          "381822964866-lt575n2vlmaduii4e0j5kn1ba6fq4a3b.apps.googleusercontent.com",

        // --- Billing (RevenueCat). See docs/monetization.md. ---------------

        // Secrets: read from api/.env.local by `npm run deploy`. Optional, so
        // the API deploys without them (billing routes then answer 503).
        REVENUECAT_SECRET_KEY: { value: process.env.REVENUECAT_SECRET_KEY, required: false },
        REVENUECAT_WEBHOOK_SECRET: {
          value: process.env.REVENUECAT_WEBHOOK_SECRET,
          required: false,
        },
        // Comma-separated Google account emails whose RevenueCat *Test Store*
        // purchases count (debug builds use the test_… SDK key). Kept in
        // .env.local, not here, because they're personal emails.
        REVENUECAT_TESTER_EMAILS: {
          value: process.env.REVENUECAT_TESTER_EMAILS,
          required: false,
        },

        REVENUECAT_ENTITLEMENT_ID: "color_blendr_pro",
        // Play test purchases come only from license testers you add in Play
        // Console, so counting them is safe and lets you test on production.
        REVENUECAT_ALLOW_SANDBOX: "true",
        REVENUECAT_ALLOWED_STORES: "play_store,promotional",
      },
    },
  },
});
