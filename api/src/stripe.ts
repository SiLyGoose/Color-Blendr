// Selling Pro on the web with Stripe's own Checkout page.
//
// The API creates the Checkout Session, so prices and the buyer's account id
// come from here, never from the browser. The account id goes into the
// session's and the subscription's metadata (`app_user_id`), which is how
// RevenueCat's Stripe integration files the purchase under the same customer
// as the Android app. After checkout the API also posts the subscription to
// RevenueCat directly, so Pro turns on without waiting for Stripe's
// notification. Whether the account has Pro is still read back from
// RevenueCat (see billing.ts), never from Stripe or the browser.
//
// Plain fetch against Stripe's REST API (form-encoded), like billing.ts does
// for RevenueCat: four calls don't need the SDK.

import { z } from "zod";

export type StripeMode = "live" | "test";

export const PLAN_IDS = ["monthly", "yearly"] as const;
export type PlanId = (typeof PLAN_IDS)[number];

/** One way to buy Pro, as the web paywall shows it. */
export type Plan = {
  id: PlanId;
  /** In the currency's minor unit (cents). */
  amount: number;
  /** Lowercase ISO 4217, as Stripe gives it ("usd"). */
  currency: string;
  interval: "month" | "year";
};

export type StripeModeConfig = {
  /** Secret or restricted key (sk_/rk_). Server only. */
  secretKey: string;
  /** Stripe price ids (price_…) for each plan. */
  prices: Record<PlanId, string>;
  /**
   * The public API key of the Stripe config in RevenueCat, for POST
   * /v1/receipts. Optional: without it RevenueCat still picks the purchase up
   * from Stripe's notifications, just a little later.
   */
  revenueCatKey?: string;
};

export type CheckoutSession = {
  /** client_reference_id: our account id. */
  userId: string | null;
  status: string | null;
  subscriptionId: string | null;
};

export interface StripeBilling {
  /** The plans on sale, cheapest commitment first. Cached for a few minutes. */
  plans(): Promise<Plan[]>;
  /** Creates a Checkout Session and returns its URL. */
  createCheckout(input: {
    plan: PlanId;
    userId: string;
    email: string;
    successUrl: string;
    cancelUrl: string;
  }): Promise<string>;
  getCheckout(sessionId: string): Promise<CheckoutSession>;
  /** Tells RevenueCat about a subscription right away. No-op without revenueCatKey. */
  reportToRevenueCat(userId: string, subscriptionId: string): Promise<void>;
  /** A Stripe customer-portal link for the account's subscription, or null if it has none. */
  portalUrl(userId: string, returnUrl: string): Promise<string | null>;
}

export class StripeError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

/** Stripe's form encoding: nested objects become a[b][c]=v. */
export function formEncode(params: Record<string, unknown>): string {
  const out = new URLSearchParams();
  const add = (prefix: string, value: unknown) => {
    if (value === undefined || value === null) return;
    if (Array.isArray(value)) value.forEach((v, i) => add(`${prefix}[${i}]`, v));
    else if (typeof value === "object") {
      for (const [k, v] of Object.entries(value)) add(`${prefix}[${k}]`, v);
    } else out.append(prefix, String(value));
  };
  for (const [k, v] of Object.entries(params)) add(k, v);
  return out.toString();
}

const priceResponse = z.object({
  id: z.string(),
  active: z.boolean(),
  unit_amount: z.number().int().nullable(),
  currency: z.string(),
  recurring: z.object({ interval: z.string(), interval_count: z.number() }).nullable(),
});

const sessionResponse = z.object({
  url: z.string().nullish(),
  client_reference_id: z.string().nullish(),
  status: z.string().nullish(),
  subscription: z.union([z.string(), z.object({ id: z.string() })]).nullish(),
});

const searchResponse = z.object({
  data: z.array(z.object({ customer: z.union([z.string(), z.object({ id: z.string() })]) })),
});

const PLANS_TTL_MS = 5 * 60_000;

export function stripeBilling(
  cfg: StripeModeConfig,
  opts: { fetch?: typeof fetch; now?: () => number } = {},
): StripeBilling {
  const doFetch = opts.fetch ?? fetch;
  const now = opts.now ?? Date.now;

  async function stripe(method: "GET" | "POST", path: string, params?: Record<string, unknown>) {
    const query = method === "GET" && params ? `?${formEncode(params)}` : "";
    const res = await doFetch(`https://api.stripe.com${path}${query}`, {
      method,
      headers: {
        authorization: `Bearer ${cfg.secretKey}`,
        ...(method === "POST" ? { "content-type": "application/x-www-form-urlencoded" } : {}),
      },
      body: method === "POST" && params ? formEncode(params) : undefined,
      signal: AbortSignal.timeout(15_000),
    });
    const json: unknown = await res.json().catch(() => null);
    if (!res.ok) {
      const message =
        (json as { error?: { message?: string } } | null)?.error?.message ?? `HTTP ${res.status}`;
      throw new StripeError(`Stripe ${method} ${path} failed: ${message}`, res.status);
    }
    return json;
  }

  let cached: { at: number; plans: Plan[] } | null = null;

  async function loadPlan(id: PlanId): Promise<Plan | null> {
    const price = priceResponse.parse(await stripe("GET", `/v1/prices/${encodeURIComponent(cfg.prices[id])}`));
    const interval = price.recurring?.interval;
    if (!price.active || price.unit_amount === null || price.recurring?.interval_count !== 1) return null;
    if (interval !== "month" && interval !== "year") return null;
    return { id, amount: price.unit_amount, currency: price.currency, interval };
  }

  return {
    async plans() {
      if (cached && now() - cached.at < PLANS_TTL_MS) return cached.plans;
      const plans = (await Promise.all(PLAN_IDS.map(loadPlan))).filter((p): p is Plan => p !== null);
      cached = { at: now(), plans };
      return plans;
    },

    async createCheckout({ plan, userId, email, successUrl, cancelUrl }) {
      const metadata = { app_user_id: userId };
      const json = sessionResponse.parse(
        await stripe("POST", "/v1/checkout/sessions", {
          mode: "subscription",
          line_items: [{ price: cfg.prices[plan], quantity: 1 }],
          // Our account id, three ways: client_reference_id for us, metadata
          // on the session and on the subscription for RevenueCat.
          client_reference_id: userId,
          metadata,
          subscription_data: { metadata },
          // Fixed to the Google account, so the Stripe customer portal (which
          // signs in by email) finds the subscription.
          customer_email: email,
          success_url: successUrl,
          cancel_url: cancelUrl,
        }),
      );
      if (!json.url) throw new StripeError("Stripe returned a session without a URL", 502);
      return json.url;
    },

    async getCheckout(sessionId) {
      const json = sessionResponse.parse(
        await stripe("GET", `/v1/checkout/sessions/${encodeURIComponent(sessionId)}`),
      );
      const sub = json.subscription;
      return {
        userId: json.client_reference_id ?? null,
        status: json.status ?? null,
        subscriptionId: typeof sub === "string" ? sub : (sub?.id ?? null),
      };
    },

    async reportToRevenueCat(userId, subscriptionId) {
      if (!cfg.revenueCatKey) return;
      const res = await doFetch("https://api.revenuecat.com/v1/receipts", {
        method: "POST",
        headers: {
          authorization: `Bearer ${cfg.revenueCatKey}`,
          "x-platform": "stripe",
          "content-type": "application/json",
        },
        body: JSON.stringify({ app_user_id: userId, fetch_token: subscriptionId }),
        signal: AbortSignal.timeout(15_000),
      });
      if (!res.ok) throw new Error(`RevenueCat POST receipts (stripe) failed: ${res.status}`);
    },

    async portalUrl(userId, returnUrl) {
      // Our id is a UUID (checked by the caller), so it's safe inside the query.
      const found = searchResponse.parse(
        await stripe("GET", "/v1/subscriptions/search", {
          query: `metadata['app_user_id']:'${userId}'`,
          limit: 1,
        }),
      );
      const customer = found.data[0]?.customer;
      if (!customer) return null;
      const json = z.object({ url: z.string() }).parse(
        await stripe("POST", "/v1/billing_portal/sessions", {
          customer: typeof customer === "string" ? customer : customer.id,
          return_url: returnUrl,
        }),
      );
      return json.url;
    },
  };
}

/**
 * Reads one mode's settings from the environment, or undefined when it isn't
 * set up. Live: STRIPE_SECRET_KEY, STRIPE_PRICE_MONTHLY, STRIPE_PRICE_YEARLY,
 * REVENUECAT_STRIPE_KEY. Test: the same with STRIPE_TEST_… and
 * REVENUECAT_STRIPE_TEST_KEY.
 */
export function stripeConfigFromEnv(
  env: NodeJS.ProcessEnv,
  mode: StripeMode,
): StripeModeConfig | undefined {
  const p = mode === "live" ? "STRIPE" : "STRIPE_TEST";
  const secretKey = env[`${p}_SECRET_KEY`]?.trim();
  const monthly = env[`${p}_PRICE_MONTHLY`]?.trim();
  const yearly = env[`${p}_PRICE_YEARLY`]?.trim();
  if (!secretKey || !monthly || !yearly) return undefined;
  const want = mode === "live" ? "_live_" : "_test_";
  if (!/^(sk|rk)_(live|test)_/.test(secretKey) || !secretKey.includes(want)) {
    throw new Error(`${p}_SECRET_KEY must be a ${mode}-mode secret or restricted key (sk${want}… or rk${want}…)`);
  }
  for (const [name, id] of [
    ["MONTHLY", monthly],
    ["YEARLY", yearly],
  ] as const) {
    if (!id.startsWith("price_")) throw new Error(`${p}_PRICE_${name} must be a Stripe price id (price_…)`);
  }
  const rcKey = env[mode === "live" ? "REVENUECAT_STRIPE_KEY" : "REVENUECAT_STRIPE_TEST_KEY"]?.trim();
  return { secretKey, prices: { monthly, yearly }, revenueCatKey: rcKey || undefined };
}
