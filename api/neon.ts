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

        // Browser origins of the web app (repo Color-Blendr-UI, served at /app),
        // comma-separated. The Vite dev server is included for local testing;
        // it can't use anyone's session, which lives in the page's own origin.
        WEB_ORIGINS: "https://color-blendr-ui.vercel.app,http://localhost:5173",

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
        // Stores whose sandbox (test) purchases count for everyone. Play test
        // purchases come only from license testers you add in Play Console, so
        // that's safe. Never add rc_billing: anyone with the web sandbox key and
        // a Stripe test card could buy. Testers' sandbox purchases count anyway.
        REVENUECAT_SANDBOX_STORES: "play_store",
        // play_store = Android, stripe = the web app (Stripe Checkout, tracked
        // by RevenueCat's Stripe integration), rc_billing = RevenueCat Web
        // Billing (no longer sold; kept so any earlier purchase still counts),
        // promotional = grants made in the RevenueCat dashboard. Never add
        // stripe to the sandbox list: test-card purchases count for testers only.
        REVENUECAT_ALLOWED_STORES: "play_store,stripe,rc_billing,promotional",

        // --- Web sales: Stripe Checkout. See docs/web-launch-handoff.md. ----
        // All optional and read from api/.env.local. Without the live set, the
        // web app shows "Get Pro on Google Play". The test set (Stripe test
        // mode or a Stripe sandbox) is used from localhost and Vercel previews,
        // by tester accounts only.
        STRIPE_SECRET_KEY: { value: process.env.STRIPE_SECRET_KEY, required: false },
        STRIPE_PRICE_MONTHLY: { value: process.env.STRIPE_PRICE_MONTHLY, required: false },
        STRIPE_PRICE_YEARLY: { value: process.env.STRIPE_PRICE_YEARLY, required: false },
        // Public key of the Stripe config in RevenueCat (for POST /v1/receipts).
        REVENUECAT_STRIPE_KEY: { value: process.env.REVENUECAT_STRIPE_KEY, required: false },
        STRIPE_TEST_SECRET_KEY: { value: process.env.STRIPE_TEST_SECRET_KEY, required: false },
        STRIPE_TEST_PRICE_MONTHLY: { value: process.env.STRIPE_TEST_PRICE_MONTHLY, required: false },
        STRIPE_TEST_PRICE_YEARLY: { value: process.env.STRIPE_TEST_PRICE_YEARLY, required: false },
        REVENUECAT_STRIPE_TEST_KEY: {
          value: process.env.REVENUECAT_STRIPE_TEST_KEY,
          required: false,
        },
      },
    },
  },
});
