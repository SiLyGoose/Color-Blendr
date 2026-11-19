import { describe, expect, it } from "vitest";

import { formEncode, stripeBilling, stripeConfigFromEnv, type StripeModeConfig } from "../src/stripe";

const cfg: StripeModeConfig = {
  secretKey: "rk_live_x",
  prices: { monthly: "price_m", yearly: "price_y" },
  revenueCatKey: "strp_pub",
};

type Call = { url: string; method: string; headers: Record<string, string>; body?: string };

/** Answers Stripe and RevenueCat calls from [routes] by "METHOD path" prefix. */
function fakeFetch(routes: Record<string, unknown>) {
  const calls: Call[] = [];
  const doFetch = (async (input: string | URL, init?: RequestInit) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    calls.push({ url, method, headers: init?.headers as Record<string, string>, body: init?.body as string });
    const path = new URL(url).pathname;
    const key = Object.keys(routes).find((k) => `${method} ${path}`.startsWith(k));
    if (!key) return new Response(JSON.stringify({ error: { message: "no route" } }), { status: 404 });
    return new Response(JSON.stringify(routes[key]), { status: 200 });
  }) as typeof fetch;
  return { doFetch, calls };
}

const price = (id: string, amount: number, interval: string, extra = {}) => ({
  id,
  active: true,
  unit_amount: amount,
  currency: "usd",
  recurring: { interval, interval_count: 1 },
  ...extra,
});

describe("stripe", () => {
  it("form-encodes nested params the way Stripe expects", () => {
    const body = new URLSearchParams(
      formEncode({ line_items: [{ price: "p", quantity: 1 }], subscription_data: { metadata: { a: "b" } }, skip: undefined }),
    );
    expect(Object.fromEntries(body)).toEqual({
      "line_items[0][price]": "p",
      "line_items[0][quantity]": "1",
      "subscription_data[metadata][a]": "b",
    });
  });

  it("loads plans from Stripe prices, drops inactive ones, and caches them", async () => {
    const { doFetch, calls } = fakeFetch({
      "GET /v1/prices/price_m": price("price_m", 499, "month"),
      "GET /v1/prices/price_y": price("price_y", 3599, "year", { active: false }),
    });
    const stripe = stripeBilling(cfg, { fetch: doFetch });
    expect(await stripe.plans()).toEqual([{ id: "monthly", amount: 499, currency: "usd", interval: "month" }]);
    await stripe.plans();
    expect(calls).toHaveLength(2);
  });

  it("puts the account id on the session and the subscription", async () => {
    const { doFetch, calls } = fakeFetch({ "POST /v1/checkout/sessions": { url: "https://checkout.stripe.com/x" } });
    const url = await stripeBilling(cfg, { fetch: doFetch }).createCheckout({
      plan: "yearly",
      userId: "u1",
      email: "a@example.com",
      successUrl: "https://w/app/account?checkout=success&session_id={CHECKOUT_SESSION_ID}",
      cancelUrl: "https://w/app/",
    });
    expect(url).toBe("https://checkout.stripe.com/x");
    const sent = Object.fromEntries(new URLSearchParams(calls[0]!.body));
    expect(sent).toMatchObject({
      mode: "subscription",
      "line_items[0][price]": "price_y",
      client_reference_id: "u1",
      "metadata[app_user_id]": "u1",
      "subscription_data[metadata][app_user_id]": "u1",
      customer_email: "a@example.com",
      success_url: "https://w/app/account?checkout=success&session_id={CHECKOUT_SESSION_ID}",
    });
    expect(calls[0]!.headers.authorization).toBe("Bearer rk_live_x");
  });

  it("posts the subscription to RevenueCat with the Stripe config's public key", async () => {
    const { doFetch, calls } = fakeFetch({ "POST /v1/receipts": {} });
    await stripeBilling(cfg, { fetch: doFetch }).reportToRevenueCat("u1", "sub_1");
    expect(calls[0]!.url).toBe("https://api.revenuecat.com/v1/receipts");
    expect(calls[0]!.headers).toMatchObject({ authorization: "Bearer strp_pub", "x-platform": "stripe" });
    expect(JSON.parse(calls[0]!.body!)).toEqual({ app_user_id: "u1", fetch_token: "sub_1" });
  });

  const sub = (extra = {}) => ({
    id: "sub_1",
    status: "active",
    created: 1_700_000_000,
    customer: "cus_1",
    cancel_at: null,
    cancel_at_period_end: false,
    ended_at: null,
    items: {
      data: [
        {
          current_period_end: 1_800_000_000,
          price: { id: "price_m", unit_amount: 499, currency: "usd", recurring: { interval: "month" } },
        },
      ],
    },
    ...extra,
  });

  it("reads the subscription and its invoices, marking refunded ones", async () => {
    const { doFetch, calls } = fakeFetch({
      "GET /v1/subscriptions/search": { data: [sub({ id: "sub_old", status: "canceled", created: 1 }), sub()] },
      "GET /v1/invoices": {
        data: [
          {
            id: "in_2",
            created: 1_750_000_000,
            total: 499,
            currency: "usd",
            status: "paid",
            hosted_invoice_url: "https://invoice.stripe.com/i/2",
            payments: { data: [{ payment: { payment_intent: "pi_2" } }] },
          },
          { id: "in_1", created: 1_700_000_000, total: 499, currency: "usd", status: "paid", payments: { data: [] } },
          { id: "in_draft", created: 1_760_000_000, total: 499, currency: "usd", status: "draft" },
        ],
      },
      "GET /v1/charges": { data: [{ payment_intent: "pi_2", amount_refunded: 499 }] },
    });
    const result = await stripeBilling(cfg, { fetch: doFetch }).subscription("u1");
    expect(result).toMatchObject({
      status: "active",
      plan: "monthly",
      amount: 499,
      interval: "month",
      currentPeriodEnd: new Date(1_800_000_000_000).toISOString(),
      cancelAt: null,
    });
    expect(result!.invoices.map((i) => [i.id, i.refunded])).toEqual([
      ["in_2", true],
      ["in_1", false],
    ]);
    expect(calls[0]!.headers["stripe-version"]).toBeTruthy();
    expect(decodeURIComponent(calls[0]!.url)).toContain("metadata['app_user_id']:'u1'");
  });

  it("cancels with the flag, and resumes whichever way it was cancelled", async () => {
    const run = async (current: object, cancel: boolean) => {
      const { doFetch, calls } = fakeFetch({
        "GET /v1/subscriptions/search": { data: [sub(current)] },
        "POST /v1/subscriptions/sub_1": {},
      });
      expect(await stripeBilling(cfg, { fetch: doFetch }).setCancelAtPeriodEnd("u1", cancel)).toBe("sub_1");
      const post = calls.find((c) => c.method === "POST");
      return post ? Object.fromEntries(new URLSearchParams(post.body)) : null;
    };
    expect(await run({}, true)).toEqual({ cancel_at_period_end: "true" });
    expect(await run({ cancel_at_period_end: true, cancel_at: 1_800_000_000 }, false)).toEqual({ cancel_at_period_end: "false" });
    // Stripe's portal (newer API versions) sets only cancel_at.
    expect(await run({ cancel_at: 1_800_000_000 }, false)).toEqual({ cancel_at: "" });
    expect(await run({ cancel_at: 1_800_000_000 }, true)).toBeNull(); // Already ending.
  });

  it("won't touch a subscription that has ended", async () => {
    const { doFetch, calls } = fakeFetch({ "GET /v1/subscriptions/search": { data: [sub({ status: "canceled" })] } });
    expect(await stripeBilling(cfg, { fetch: doFetch }).setCancelAtPeriodEnd("u1", true)).toBeNull();
    expect(calls.every((c) => c.method === "GET")).toBe(true);
  });

  it("reads mode settings from the environment and rejects mixed-up keys", () => {
    const env = {
      STRIPE_SECRET_KEY: "rk_live_abc",
      STRIPE_PRICE_MONTHLY: "price_1",
      STRIPE_PRICE_YEARLY: "price_2",
      REVENUECAT_STRIPE_KEY: "strp_x",
    };
    expect(stripeConfigFromEnv(env, "live")).toEqual({
      secretKey: "rk_live_abc",
      prices: { monthly: "price_1", yearly: "price_2" },
      revenueCatKey: "strp_x",
    });
    expect(stripeConfigFromEnv(env, "test")).toBeUndefined();
    expect(() => stripeConfigFromEnv({ ...env, STRIPE_SECRET_KEY: "sk_test_abc" }, "live")).toThrow();
    expect(() => stripeConfigFromEnv({ ...env, STRIPE_PRICE_YEARLY: "prod_2" }, "live")).toThrow();
  });
});
