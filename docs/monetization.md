# Monetization: Color Blendr Pro

Pro is sold as **Monthly** ($4.99) and **Yearly** ($35.99) subscriptions, on
Google Play and on the web (Stripe Checkout, §6). There's no lifetime option
(dropped 2026-11-19; the API still handles one-time purchases). Purchases are
verified by **RevenueCat**, and both grant the RevenueCat entitlement
**`color_blendr_pro`**. The Color Blendr API is the only thing
that decides whether an account has Pro.

```
 App (purchases_flutter, public key goog_…)
   │  1. buy with Play Billing ──────────────► Google Play
   │  2. SDK sends the purchase token ───────► RevenueCat ──verifies token──► Google Play API
   │  3. POST /v1/billing/sync (session only) ─► Color Blendr API
   │                                               │  4. GET /v1/subscribers/{user id}
   │                                               │     (secret key sk_…) ──► RevenueCat
   │  5. { plan: "pro", … } ◄──────────────────────┘
   │
 RevenueCat ── webhook "something changed for user X" ──► POST /v1/billing/revenuecat
   (renewals, cancellations, refunds, expiry)              → re-reads X from RevenueCat (step 4)
```

The app never says "I paid". It buys, then asks the API to check. The API asks
RevenueCat. RevenueCat has already checked the purchase with Google.

---

## 1. What the backend already does (api/)

| Piece | Where |
|---|---|
| Store columns on `users`: `store_plan`, `store_pro_expires_at`, `store_product_id`, `store_will_renew`, `store_billing_issue`, `store_synced_at` | `src/db/schema.ts`, migration `drizzle/0002_billing.sql` |
| `billing_events` table: an audit log of webhook deliveries (never used to decide Pro) | same |
| RevenueCat client: reads the customer with the secret key and turns the `color_blendr_pro` entitlement into a plan (subscriptions and the lifetime one-time purchase) | `src/billing.ts` |
| `POST /v1/billing/sync`: re-reads the signed-in user from RevenueCat and returns the profile. Ignores the request body. At most one RevenueCat read per user every 10 s | `src/app.ts` |
| `POST /v1/billing/revenuecat`: the webhook. Checks the shared secret, logs the event, re-reads every customer it names (including both sides of a `TRANSFER`) | `src/app.ts` |
| `DELETE /v1/me` also deletes the RevenueCat customer (best effort) and the user's billing log | `src/app.ts` |
| `GET /v1/me` adds `subscription: { productId, expiresAt, willRenew, billingIssue }` (null without a store purchase). `plan`, `proExpiresAt` and `limits` keep their shape | `src/app.ts` |

The hand-granted Pro columns (`plan`, `pro_expires_at`) are separate from the
store columns. A store sync never overwrites a support grant. The account is Pro
if either one is active.

With the RevenueCat secrets unset, the API runs as before and the billing routes
return 503.

Tests: `api/test/billing.test.ts` (parsing RevenueCat responses, webhook auth)
and the `billing` block in `api/test/app.test.ts`. The SQL path in
`api/test/store.sql.test.ts` was run against a throwaway Neon branch.

---

## 2. Setup checklist (one-time, in this order)

### Google Play Console
1. **Payments profile / merchant account**: Settings → Payments profile. Needed before you can sell anything.
2. **Create the products**: Monetize → Products.
   - Subscriptions → Create: one subscription `pro` with two auto-renewing base plans, `monthly` (1 month) and `yearly` (1 year). RevenueCat names them `pro:monthly` and `pro:yearly`. Optional: a free-trial offer with eligibility "New customer acquisition → never had this subscription".
   - No lifetime product (dropped 2026-11-19). Prices: `monthly` $4.99, `yearly` $35.99.
3. **License testers**: Settings → License testing. Add your Google account(s). Their purchases are free test purchases that renew fast (a monthly sub renews every 5 minutes).
4. Upload a build that includes the billing library (the RevenueCat SDK adds it) to the **internal testing** track. Play doesn't show products to an app that has never shipped billing.

### Google Cloud (project 381822964866)
5. Create a **service account** for RevenueCat and invite it in Play Console (Users and permissions) with *View financial data* and *Manage orders and subscriptions*. Download its JSON key and upload it to RevenueCat (step 8). Then delete the local JSON file. It never goes in this repo.
6. **Real-time developer notifications (RTDN)**: create a Pub/Sub topic, give `google-play-developer-notifications@system.gserviceaccount.com` the Publisher role on it, and set it under Play Console → Monetization setup. RevenueCat's Play setup page shows the exact topic and walks through it. **Don't skip this.** Without RTDN, RevenueCat learns about refunds and cancellations late.

### RevenueCat
7. Create a project and add a **Google Play app** with package `org.ColorBlendr.color_blendr`.
8. Upload the service-account JSON from step 5 and connect RTDN (step 6).
9. **Entitlement** `color_blendr_pro`. Attach `pro:monthly` and `pro:yearly`. Do the same for the Test Store products `monthly` and `yearly`.
10. **Offering** `default` (mark it current) with packages `$rc_monthly` → monthly and `$rc_annual` → yearly. No `$rc_lifetime` package: the app shows every package in the offering. Attach a RevenueCat Paywall to it if the app uses RevenueCat's paywall UI.
11. Project settings → **Restore behavior / transfer behavior: "Keep with original App User ID"**. This stops one subscription from unlocking several accounts (see §4).
12. **Webhook**: Integrations → Webhooks → add
    - URL: `https://br-empty-smoke-bc031jex-api.compute.c-16.us-east-1.aws.neon.tech/v1/billing/revenuecat`
    - Authorization header value: `Bearer <REVENUECAT_WEBHOOK_SECRET>`, exactly, including the word `Bearer`.
    - Environment: both production and sandbox.
13. Copy two keys from API keys:
    - **Public Google SDK key** (`goog_…`). Goes in the app. Safe to ship.
    - **Secret key** (`sk_…`, v1). Goes **only** in `api/.env.local`. It can read and change any customer, so never put it in the app or in git.

### API
14. Add the secrets to `api/.env.local` (it's in `.gitignore`). `neon.ts` passes them to the function at deploy time:
    ```
    REVENUECAT_SECRET_KEY=sk_...
    REVENUECAT_WEBHOOK_SECRET=<output of the command below>
    REVENUECAT_TESTER_EMAILS=you@gmail.com
    ```
    Generate the webhook secret with:
    `node -e "console.log(require('crypto').randomBytes(32).toString('base64url'))"`
15. Non-secret settings live in `api/neon.ts`: `REVENUECAT_ENTITLEMENT_ID=color_blendr_pro`, `REVENUECAT_SANDBOX_STORES=play_store` (stores whose test purchases count for everyone), `REVENUECAT_ALLOWED_STORES=play_store,rc_billing,promotional`.
16. Deploy: `cd api && npm run deploy`. Migrations 0001 and 0002 were applied to production on 2026-11-17. Future schema changes: run `npm run db:migrate` first, then deploy.
17. Send a **test webhook** from the RevenueCat dashboard. It should return 200 and add a `TEST` row to `billing_events`.

### Testing with the RevenueCat Test Store (`test_…` key)

RevenueCat's Test Store lets debug builds buy without any Play setup. A modal
lets you simulate success, failure or cancellation, and subscriptions renew on
a fast schedule. Test Store purchases are free, so:

- **The production API ignores them**, except on accounts listed in `REVENUECAT_TESTER_EMAILS`. For those accounts it counts sandbox purchases from any store. Put only your own Google accounts there.
- **The test key must never be in a release build.** The SDK crashes on purpose in a release build that has a Test Store key. Play's internal, closed and open testing builds are release builds, so test those with the `goog_…` key and Play license testers.
- Pass the key per build instead of hard-coding it: `flutter run --dart-define=REVENUECAT_GOOGLE_KEY=test_…` for debug, and `--dart-define=REVENUECAT_GOOGLE_KEY=goog_…` for release.
- If a purchase doesn't unlock Pro, check the API logs. The API logs a line like `Ignoring "color_blendr_pro" entitlement (…): store … not allowed` that says exactly why.

---

## 3. The app side (Flutter, built 2026-11-17)

Uses `purchases_flutter` with the app's own paywall. It doesn't use RevenueCat
Paywalls or Customer Center: you chose the built-in paywall, so
`purchases_ui_flutter` isn't a dependency and `MainActivity` stays
`FlutterActivity`.

| Piece | Where | What it does |
|---|---|---|
| Key | `lib/app/config.dart` | `--dart-define=REVENUECAT_GOOGLE_KEY=…`. `canSellWith(key, releaseBuild: kReleaseMode)` turns billing off when a release build has a `test_…` key, because the SDK would crash. No key means `UnavailableBilling`. |
| Billing | `lib/data/billing.dart` | Identifies the user with our account id (never anonymous), logs out on sign-out and account deletion, loads every package in the current offering (sorted weekly → … → annual → lifetime), and buys with `Purchases.purchase(PurchaseParams…)`. |
| Paywall | `lib/ui/pro/pro_sheet.dart` | Shows the plans as choices, with Yearly pre-selected and a "Save N%" badge against Monthly. Terms read "X per year, renews automatically. Cancel anytime in Google Play." for subscriptions, or "X once. One-time purchase, no subscription." for Lifetime. No restore button: Pro belongs to the account and follows sign-in, and the RevenueCat SDK sends any unfinished Play purchase when the app opens. |
| Activation | `lib/state/auth_controller.dart` | After a purchase: `POST /v1/billing/sync`, then once more after 11 s if Pro isn't on yet (the API waits 10 s between checks). If it still isn't, the sheet says "Purchase received, Pro will turn on in a minute" and the webhook catches up. |
| Settings | `lib/ui/settings/settings_page.dart` | Shows "Renews on" / "Ends on" / "Lifetime", a payment-problem line, and Manage subscription (Play URL, subscriptions only). Warns before account deletion when `willRenew`. |
| Refresh | `lib/ui/home_shell.dart` | Re-reads the plan when the app comes back to the foreground. |

The app never reads the entitlement id or unlocks from `CustomerInfo`.
`isProProvider` follows the API's `plan`.

**Still to do: an end-to-end test.**
1. Do the setup checklist (§2), including `REVENUECAT_TESTER_EMAILS`, and deploy the API.
2. Debug build with the Test Store: `flutter run --dart-define=REVENUECAT_GOOGLE_KEY=test_…`, signed in as a tester email. Buy each plan, cancel, reinstall and sign in again (Pro should come back on its own), and let a subscription expire (Test Store renews fast). Check that Pro, Settings and `billing_events` follow each step.
3. Internal-testing build with the `goog_…` key and a Play license tester: repeat the steps against real Play Billing, including a refund from Play Console.

---

## 4. Stopping people from getting Pro without paying

### Rule 1: the device is never trusted
Treat everything on a rooted or jailbroken phone as attacker-controlled: the
app's code, its memory, its network traffic, and the Play Billing responses it
receives. So:

- **The API never takes a client's word.** `/v1/billing/sync` ignores the body. Pro comes only from RevenueCat, read with a secret key the app doesn't have.
- **RevenueCat checks every purchase token with Google's servers** (using the service account from step 5). Tools like Lucky Patcher, "Freedom" or billing emulators fake the Play Billing *response on the device*. The fake token they produce fails Google's server check, so RevenueCat records no purchase and the API grants nothing.
- **Pro limits are enforced on the server.** The 10-palette limit, folders and tags are checked in `src/app.ts`. A patched app that thinks it's Pro just gets `402` back.

### How each attack is handled

| Attack | What stops it |
|---|---|
| Fake purchase from a billing-hack tool or emulator | Google rejects the token when RevenueCat checks it, so no entitlement. |
| Modified app claims `isPro` or sends a fake receipt to our API | The API has no endpoint that accepts a receipt or plan. Pro is read from RevenueCat server-side. |
| Forged webhook ("user X bought Pro") | Needs the shared secret (constant-time compare). Even with the secret, the payload is ignored: the API re-reads X from RevenueCat, which says what X really owns. |
| Replayed or out-of-order webhooks | Every webhook triggers a fresh read, so order doesn't matter. `store_synced_at` stops an older read from overwriting a newer one. |
| Leaked public SDK key (`goog_…`) | It's meant to be public. With it, you can only attach real, Google-checked purchases to a customer. It can't grant entitlements. |
| Leaked secret key (`sk_…`) | That would be serious, so it lives only in `.env.local` on the server. Rotate it in RevenueCat if it ever leaks. |
| One subscription shared across many accounts (buying again from a friend's account on the same Google account) | RevenueCat restore behavior "Keep with original App User ID" (step 11). A purchase stays with the account that bought it. |
| Buy, use, refund | Play refund → RTDN → RevenueCat removes the entitlement → webhook → API removes Pro. Needs RTDN (step 6). |
| Test or sandbox purchases | On Play, only license testers you add can make them, so `REVENUECAT_SANDBOX_STORES=play_store` counts them for everyone. Web sandbox purchases (Stripe test cards) count only for `REVENUECAT_TESTER_EMAILS`: anyone could use a test card if the sandbox key leaked. The store allowlist ignores RevenueCat's Test Store and other stores. Never add `app_store` to the sandbox list if this ships on iOS, where anyone with TestFlight gets sandbox purchases. |
| Leaked web key (`rcb_…`) | Public by design, like `goog_…`: it can only start a real, paid Stripe checkout. The web app also refuses to sell with a sandbox key (`rcb_sb_…`) on the live domain. |
| Free-trial farming | Play allows one trial per Google account per subscription when eligibility is "never had this subscription". People with many Google accounts can still farm trials. Keep any trial short. |
| Spamming `/v1/billing/sync` to burn the RevenueCat rate limit | At most one RevenueCat read per user every 10 s. |
| RevenueCat outage | Errors are thrown, never read as "free", so Pro isn't stripped by an outage. The webhook returns 500 and RevenueCat retries. |

### What can't be fully protected: features that run only on the device
**Export formats, palettes from photos, and the accessibility checks** run
entirely on the phone. The app decides whether to show them using `isPro`. Someone
who decompiles and re-signs the APK can flip that check and use these features
offline. **No app can fully prevent this**, whatever the payment provider.
What raises the cost:

1. **Obfuscate release builds** (cheap, do it now):
   `flutter build appbundle --obfuscate --split-debug-info=build/symbols`
   Keep `build/symbols` for each release so you can read crash stack traces.
2. **Play Integrity API** (optional, later). The app asks Google for a signed
   verdict, and the API checks it server-side via `decodeIntegrityToken`. A
   re-signed APK fails `appRecognitionVerdict == PLAY_RECOGNIZED`. Use it to
   refuse *server* features (sign-in, sync, saves) to tampered builds. Caveats:
   - It can't protect code that runs only on the device. A cracker removes the check along with the Pro check.
   - Many honest users are on custom ROMs or rooted phones. Don't block **paying** over a device-integrity verdict. If you use it, require `PLAY_RECOGNIZED` (app not tampered), not `MEETS_STRONG_INTEGRITY`.
3. **Move high-value work to the server** if a feature is worth protecting. For example, generate export files or image palettes on the API, or make them depend on the cloud library, which is already enforced on the server.

For an app this size, a few people cracking the offline features is normal and
usually not worth fighting further. The server-side setup above ensures nobody
gets **cloud Pro** (unlimited saves, folders, tags, sync across devices) without
a purchase Google has verified.

---

## 5. Ads (AdMob, added 2026-11-17)

Free accounts and signed-out users see a full-screen AdMob interstitial on every
fifth palette they ask for (the Generate button, or swiping past the newest
palette). Never two within 60 s (`AdsController.minGap`): AdMob's policies rule
out ads after every few taps. When the user closes the ad, the upgrade sheet
opens headed "Go ad-free". Pro removes ads: there is no separate "remove ads"
product. Pro accounts never load the ad SDK or see the consent form.

| Piece | Where |
|---|---|
| AdMob interstitials and Google's consent form (UMP) | `lib/data/ads.dart` |
| Counting, pacing, Pro check | `lib/state/ads_controller.dart` |
| Ad, then the offer | `_generateByUser` in `lib/ui/generator/generator_page.dart` |
| "Ad privacy choices" (EEA/UK only) | `lib/ui/settings/settings_page.dart` |
| Unity Ads and Liftoff Monetize mediation adapters | `pubspec.yaml` (`gma_mediation_unity`, `gma_mediation_liftoffmonetize`, pinned to versions that match `google_mobile_ads`) |
| R8 rules for OkHttp (from the Liftoff SDK) | `android/app/proguard-rules.pro` |
| US "do not sell or share" choice, passed to Unity and Liftoff | `lib/data/us_privacy.dart`, read through the `privacy` channel in `MainActivity.kt` |

**Mediation (Unity Ads, added 2026-11-19).** Unity Ads bids against Google for
each interstitial through AdMob mediation. The adapter registers itself, so
there's no other ad code. It picks up GDPR consent from the consent form by
itself. The US-state opt-out isn't passed on automatically, so before the SDK
starts (and after Ad privacy choices) the app reads it from the IAB GPP strings
the consent form saves and calls `setCCPAConsent`. A US section the decoder
can't read counts as opted out. The same code is in Tidy Town.

Unity setup (Unity dashboard → Monetization): Color Blendr is its own Android
app there, Game ID `800445678`, interstitial placement `BP_Interstitial_Android`
(Tidy Town's Game ID is different, don't mix them up). It's mapped in AdMob's
Android interstitial mediation group under **Bidding → Unity Ads**. Its
app-ads.txt lines are in the Color-Blendr-UI repo (`site/app-ads.txt`), and
the privacy policy there names Unity. Also add **Unity Ads** to the ad partners
in both AdMob Privacy & messaging messages, and check fill with AdMob →
Mediation → Ad inspector on a test device.

**Liftoff Monetize (added 2026-11-19)** works the same way: the app passes the
US opt-out with `setCCPAStatus`. Liftoff dashboard: Color Blendr is its own
Android app, app id `6aff31f09dacaf6546996601`, interstitial placement
`v1-generate` (reference id `V1_GENERATE-6268923`), in-app bidding on. Ignore
Liftoff's "download the SDK" steps: the adapter brings the SDK. In AdMob, add
it under **Bidding → Liftoff Monetize** in the interstitial mediation group
(it also asks for Liftoff's reporting API key), and add **Liftoff** to the ad
partners in both Privacy & messaging messages. Its app-ads.txt line
(`vungle.com, …`) is in `site/app-ads.txt`, and the privacy policy names it.

Setup before release:

1. Create the app and an **Interstitial** ad unit in AdMob, and link the app to
   Play.
2. Put the app id in `android/local.properties`: `admob.appId=ca-app-pub-…~…`.
   Without it the build uses Google's sample app id.
3. The ad unit id is the default of `AppConfig.adMobInterstitialId`
   (`lib/app/config.dart`). Release builds use it; debug builds always show
   Google's test ads.
4. AdMob → Privacy & messaging: publish a GDPR message (and a US states
   message if you want). The consent form only appears once that exists.
5. Publish `app-ads.txt` on the developer website listed in Play.
6. Play Console: App content → Ads → "Yes, contains ads". Update Data safety:
   the Google Mobile Ads SDK collects the advertising ID, approximate location
   and app interactions, and shares them for advertising.
7. Don't click your own live ads. Add your phone as a test device in AdMob.

## 6. Selling on the web (Stripe Checkout, changed 2026-11-19)

The web app (repo Color-Blendr-UI, `/app`) sells Pro on **Stripe's own Checkout page** (checkout.stripe.com), which buyers recognize. On 2026-11-17 it used RevenueCat Web Billing's on-page checkout instead; the user switched on 2026-11-19 for the familiar Stripe page. Plans: **monthly $4.99** and **yearly $35.99** (shown as $2.99/month, billed annually). **No lifetime** anywhere, Play included.

How it fits together (code: `api/src/stripe.ts`, routes in `api/src/app.ts`):
1. The Pro dialog loads plans from `GET /v1/billing/plans`. The API reads them from the Stripe prices in `STRIPE_PRICE_MONTHLY` / `STRIPE_PRICE_YEARLY`. No plans (Stripe not configured): the dialog points to Google Play.
2. "Continue" calls `POST /v1/billing/checkout {plan}`. The API creates the Checkout Session for the signed-in account: `client_reference_id`, and `app_user_id` in both the session and subscription metadata, all set to our account id. The email is fixed to the Google account. The browser goes to Stripe.
3. Stripe sends the buyer back to `/app/account?checkout=success&session_id=…`. The web app calls `POST /v1/billing/sync {checkoutSessionId}`. The API checks that the session is this account's and paid, posts the subscription to RevenueCat (`POST /v1/receipts`, `X-Platform: stripe`, the Stripe config's public key), then reads the entitlement back from RevenueCat as usual.
4. RevenueCat's Stripe integration also picks the purchase up from Stripe's notifications using the `app_user_id` metadata. That covers buyers who close the tab before returning, and later renewals, cancellations and refunds. Its events reach the existing webhook.

- Same RevenueCat customer and entitlement (`color_blendr_pro`) as Android, so Pro bought on either works on both. RevenueCat reports the store as `stripe`, and `REVENUECAT_ALLOWED_STORES` includes it. Stripe test-mode purchases count only for `REVENUECAT_TESTER_EMAILS`; never put `stripe` in the sandbox list.
- Test mode: the web app asks for Stripe test mode on every host except the live site (localhost, Vercel previews). The API allows it only for tester accounts, and only if the `STRIPE_TEST_*` variables are set.
- Web "Manage subscription" calls `POST /v1/billing/portal`, which opens Stripe's customer portal (cancel, change card, invoices). The API finds the customer by searching Stripe subscriptions for the account id.
- Android: a web purchase shows "Bought on the web" with **no link** (Play's payments policy).
- Deleting an account doesn't cancel a web subscription; both apps and `/delete-account` say so.
- Setup steps: `docs/web-launch-handoff.md`.

## 7. Notes and later options

- **RevenueCat pricing**: free up to $2.5k monthly tracked revenue, then 1% of revenue. The alternative is calling the Google Play Developer API (`purchases.subscriptionsv2`) and RTDN from this API directly. That's more code (acknowledging purchases within 3 days, upgrades and `linkedPurchaseToken`, Pub/Sub JWT checks), so it's only worth it if the 1% starts to hurt. `BillingProvider` in `src/billing.ts` is the seam for that swap.
- RevenueCat REST v1 `GET /v1/subscribers/{id}` creates an empty customer if none exists. That's harmless.
- `billing_events` grows forever. Prune rows older than about a year if it ever matters.
- Lifetime works like this: RevenueCat reports the one-time `lifetime` purchase with `expires_date: null`, which the API stores as Pro that never ends (`proExpiresAt: null`, `subscription.expiresAt: null`, `willRenew: false`). A refund of the lifetime purchase removes the entitlement, and the webhook removes Pro.
