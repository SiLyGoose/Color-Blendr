# Web app launch: handoff (updated 2026-11-19, switching to Stripe Checkout)

To pick this up, start a Claude Code session in this repo and say:

> Read docs/web-launch-handoff.md and let's finish the web launch.

---

## Where things stand

The web app (a Coolors-style generator with the Android app's features) is **live** at
https://color-blendr-ui.vercel.app/app. It lives in the separate repo
`../Color-Blendr-UI` (`app/`), built with React, TypeScript and Vite.

On 2026-11-19 the user chose **Stripe's own Checkout page** over RevenueCat Web Billing's
on-page checkout, because buyers recognize it. They also set the prices: **$4.99/month** and
**$35.99/year** (shown as $2.99/month, billed annually). **Lifetime is gone**, on Play too.
How it works: `docs/monetization.md` §6.

| Piece | State |
|---|---|
| API deployed with web CORS (sign-in and library work on the live site) | Done 2026-11-19 |
| Stripe account "Lymon" verified and connected to RevenueCat (Live) | Done 2026-11-19 |
| API: Stripe Checkout routes (`/v1/billing/plans`, `/checkout`, `/portal`, sync with `checkoutSessionId`) | Written 2026-11-19, **not committed or deployed** |
| Web app: Stripe Checkout, price lines, custom scrollbar, `.env.local` fix | Written 2026-11-19, **not committed or pushed** |
| Site copy: no lifetime, prices on the landing page, Stripe in privacy and terms | Written 2026-11-19, **not committed or pushed** |
| Stripe products and prices, restricted key, customer portal | **To do (user)** |
| RevenueCat Stripe config, products, entitlement | **To do (user)** |
| RevenueCat Billing web config from 11/19 (`pro_*_web` products) | No longer used: take out of the offering, then delete |

Until the API has its Stripe variables, the Pro dialog on the web says "Get Pro on Google Play".

---

## Steps, in order

### 1. Stripe (dashboard.stripe.com, **live mode**)
1. **Product catalog → + Add product**, twice. Use one price per product, as RevenueCat recommends:
   - `Color Blendr Pro Monthly`: recurring, **$4.99 USD**, monthly.
   - `Color Blendr Pro Yearly`: recurring, **$35.99 USD**, yearly.

   Copy each **price id** (`price_…`). It's on the product page, under Pricing.
2. **Settings → Billing → Customer portal**: activate it. Allow canceling (at the end of
   the period), updating the payment method, and invoice history. Add the links to
   `/terms` and `/privacy`.
3. **Settings → Branding**: icon and brand color, so the checkout page says Color Blendr.
   **Settings → Public details**: support email `lymon4457@gmail.com`, website, and a
   statement descriptor such as `COLORBLENDR`.
4. **Developers → API keys → Create restricted key** named `color-blendr-api`, with:
   - Checkout Sessions: **Write**
   - Customer portal: **Write**
   - Prices: **Read**
   - Subscriptions: **Read**
   - Products: **Read**
   - everything else: None

   It starts with `rk_live_`. **Don't paste it in chat**; it goes in `api/.env.local` (step 3).

### 2. RevenueCat
1. **Apps & providers → Web → + New → Stripe** (Stripe Billing). Select the **Lymon** account.
2. **Purchase tracking** tab:
   - turn on tracking new purchases from Stripe's server-to-server notifications
   - set the **metadata field key** to **`app_user_id`**
   - leave recognition at "when the invoice has been paid"
3. **Subscription management** tab: paste the Stripe customer-portal login link
   (Stripe → Settings → Billing → Customer portal). The web app opens the portal through the
   API anyway, so this is only a fallback.
4. **Product catalog → Products → Import** on the Stripe config. Import both products,
   then attach them to the entitlement **`color_blendr_pro`**. The web app doesn't read
   offerings, so the offering doesn't need them.
5. Copy the Stripe config's **public API key** (API keys page, or the config's page).
6. **Offering `default`**:
   - remove the `pro_*_web` products from the packages
   - **delete the `$rc_lifetime` package**, otherwise Android keeps showing Lifetime
   - then delete the old RevenueCat Billing web config and its products
7. **Webhook** (Integrations → Webhooks, ending in `/v1/billing/revenuecat`): make sure it
   covers **all apps**, including the new Stripe config, in production and sandbox.

### 3. API settings and deploy
Add these to `api/.env.local` (gitignored):
```
STRIPE_SECRET_KEY=rk_live_…
STRIPE_PRICE_MONTHLY=price_…
STRIPE_PRICE_YEARLY=price_…
REVENUECAT_STRIPE_KEY=…        # the RevenueCat Stripe config's public key (step 2.5)
```
Then deploy. Auto mode blocks Claude from deploying, so type this yourself:
```
! cd api && npm test && npm run deploy
```
Check: open the Pro dialog on https://color-blendr-ui.vercel.app/app while signed in. It
should show Monthly $4.99/month ($59.88/year) and Yearly $2.99/month (Billed $35.99 annually).

### 4. Push the web app
Commit and push `../Color-Blendr-UI` (Vercel deploys `main`). If `VITE_REVENUECAT_WEB_KEY`
is set in Vercel, delete it; nothing reads it any more.

### 5. Test
Pick one of these:
- **Live, then refund** (simplest): on the live site, buy Monthly with your own card. Check
  `node --no-warnings --env-file=.env.local scripts/plan-state.mjs` in `api/` for
  `store_plan = pro` and `store_name = stripe`. Then refund the payment in Stripe
  (Payments → the charge → Refund) and cancel the subscription. Pro should turn off within
  a few minutes. Stripe keeps its fee, about $0.45.
- **Test mode** (optional): create a Stripe **sandbox** and install the RevenueCat app in
  it. Connect it in RevenueCat and make a second Stripe config for it (steps 2.1–2.5).
  Then create the same two products and a restricted key in the sandbox, and set
  `STRIPE_TEST_SECRET_KEY`, `STRIPE_TEST_PRICE_MONTHLY`, `STRIPE_TEST_PRICE_YEARLY` and
  `REVENUECAT_STRIPE_TEST_KEY`. Redeploy, then buy on http://localhost:5173/app with card
  `4242 4242 4242 4242`, signed in as an account in `REVENUECAT_TESTER_EMAILS`.

Also try: Account → **Manage subscription**, which should open Stripe's portal, and
cancel from there.

### 6. Google Play (same prices)
Subscription `pro`: base plan `monthly` **$4.99** and `yearly` **$35.99**. Don't create
`lifetime`. In RevenueCat, import only `pro:monthly` and `pro:yearly`.

---

## Things to know

- **The API decides who has Pro, never the browser or Stripe.** It reads RevenueCat with
  the secret key. The account id travels in the Checkout Session (`client_reference_id`, and
  `app_user_id` metadata on the session and the subscription), so RevenueCat files the
  purchase under the same customer as Android.
- **Sandbox rules** (`api/neon.ts`): `REVENUECAT_ALLOWED_STORES=play_store,stripe,rc_billing,promotional`,
  `REVENUECAT_SANDBOX_STORES=play_store`. Never add `stripe` to the sandbox list: anyone
  with a test card could get Pro.
- **Refund policy** (`/refunds`): a full refund within 14 days of any charge. Web refunds go
  through Stripe; Play refunds go through Play Console after Google's 48 hours.
- **Terms** (`/terms`): California law. The operator is a California resident, temporarily
  in Virginia. Stripe identity uses the current Virginia address.
- **Deleting an account doesn't cancel a web subscription.** The app, the web app and
  `/delete-account` all say so.

## Not committed on purpose
- `api/scripts/` (plan-state, reset-test-purchases, tester-check): local test helpers.
