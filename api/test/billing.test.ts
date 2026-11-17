import { describe, expect, it } from "vitest";

import {
  NO_ENTITLEMENT,
  entitlementFromSubscriber,
  revenueCatProvider,
  webhookAuthorized,
  webhookCustomerIds,
} from "../src/billing";

const now = new Date("2026-11-17T12:00:00Z");
const opts = {
  entitlementId: "pro",
  allowSandbox: false,
  allowedStores: ["play_store", "promotional"],
};

/** A RevenueCat v1 subscriber with one Play subscription to "pro:weekly". */
function subscriber(
  sub: Record<string, unknown> = {},
  ent: Record<string, unknown> = {},
) {
  return {
    request_date: now.toISOString(),
    subscriber: {
      original_app_user_id: "u1",
      entitlements: {
        pro: {
          expires_date: "2026-11-20T12:00:00Z",
          grace_period_expires_date: null,
          product_identifier: "pro:weekly",
          purchase_date: "2026-11-13T12:00:00Z",
          ...ent,
        },
      },
      subscriptions: {
        "pro:weekly": {
          store: "play_store",
          is_sandbox: false,
          expires_date: "2026-11-20T12:00:00Z",
          unsubscribe_detected_at: null,
          billing_issues_detected_at: null,
          refunded_at: null,
          ...sub,
        },
      },
      non_subscriptions: {},
    },
  };
}

describe("entitlementFromSubscriber", () => {
  it("an active Play subscription is Pro until it expires", () => {
    expect(entitlementFromSubscriber(subscriber(), now, opts)).toEqual({
      plan: "pro",
      expiresAt: new Date("2026-11-20T12:00:00Z"),
      productId: "pro:weekly",
      willRenew: true,
      billingIssue: false,
    });
  });

  it("no entitlement, or a different one, is free", () => {
    const body = subscriber();
    body.subscriber.entitlements = {} as never;
    expect(entitlementFromSubscriber(body, now, opts)).toEqual(NO_ENTITLEMENT);
    expect(
      entitlementFromSubscriber(subscriber(), now, { ...opts, entitlementId: "other" }),
    ).toEqual(NO_ENTITLEMENT);
  });

  it("an expired entitlement is free but keeps its end date", () => {
    const e = entitlementFromSubscriber(
      subscriber({}, { expires_date: "2026-11-01T00:00:00Z" }),
      now,
      opts,
    );
    expect(e).toMatchObject({ plan: "free", willRenew: false });
    expect(e.expiresAt).toEqual(new Date("2026-11-01T00:00:00Z"));
  });

  it("a billing grace period keeps Pro and flags the issue", () => {
    const e = entitlementFromSubscriber(
      subscriber(
        { billing_issues_detected_at: "2026-11-16T00:00:00Z" },
        { expires_date: "2026-11-16T00:00:00Z", grace_period_expires_date: "2026-11-19T00:00:00Z" },
      ),
      now,
      opts,
    );
    expect(e).toMatchObject({ plan: "pro", billingIssue: true });
    expect(e.expiresAt).toEqual(new Date("2026-11-19T00:00:00Z"));
  });

  it("a cancelled subscription stays Pro until it ends but won't renew", () => {
    const e = entitlementFromSubscriber(
      subscriber({ unsubscribe_detected_at: "2026-11-15T00:00:00Z" }),
      now,
      opts,
    );
    expect(e).toMatchObject({ plan: "pro", willRenew: false });
  });

  it("sandbox purchases count only when allowed", () => {
    const body = subscriber({ is_sandbox: true });
    expect(entitlementFromSubscriber(body, now, opts)).toEqual(NO_ENTITLEMENT);
    expect(entitlementFromSubscriber(body, now, { ...opts, allowSandbox: true }).plan).toBe("pro");
  });

  it("purchases from other stores don't count", () => {
    for (const store of ["test_store", "app_store", null]) {
      expect(entitlementFromSubscriber(subscriber({ store }), now, opts), String(store)).toEqual(
        NO_ENTITLEMENT,
      );
    }
  });

  it("tester accounts can use Test Store (sandbox) purchases; others can't", () => {
    const body = subscriber({ store: "test_store", is_sandbox: true });
    expect(entitlementFromSubscriber(body, now, opts)).toEqual(NO_ENTITLEMENT);
    expect(entitlementFromSubscriber(body, now, opts, { tester: true }).plan).toBe("pro");
    // Even a tester needs the purchase to be a test one from an unlisted store.
    const real = subscriber({ store: "app_store", is_sandbox: false });
    expect(entitlementFromSubscriber(real, now, opts, { tester: true })).toEqual(NO_ENTITLEMENT);
  });

  it("a lifetime purchase never ends", () => {
    const body = subscriber({}, { expires_date: null, product_identifier: "pro_lifetime" });
    body.subscriber.subscriptions = {} as never;
    (body.subscriber.non_subscriptions as Record<string, unknown>) = {
      pro_lifetime: [{ id: "x", store: "play_store", is_sandbox: false }],
    };
    expect(entitlementFromSubscriber(body, now, opts)).toMatchObject({
      plan: "pro",
      expiresAt: null,
      willRenew: false,
    });
  });

  it("rejects a malformed response instead of guessing", () => {
    expect(() => entitlementFromSubscriber({ nope: true }, now, opts)).toThrow();
  });
});

describe("revenueCatProvider", () => {
  it("reads the subscriber with the secret key", async () => {
    const calls: { url: string; init?: RequestInit }[] = [];
    const provider = revenueCatProvider({
      ...opts,
      secretKey: "sk_test",
      fetch: (async (url: string, init?: RequestInit) => {
        calls.push({ url, init });
        return new Response(JSON.stringify(subscriber()), { status: 200 });
      }) as typeof fetch,
    });
    expect((await provider.getEntitlement("a b", now)).plan).toBe("pro");
    expect(calls[0]!.url).toBe("https://api.revenuecat.com/v1/subscribers/a%20b");
    expect((calls[0]!.init!.headers as Record<string, string>).authorization).toBe("Bearer sk_test");
  });

  it("throws on errors rather than reporting free", async () => {
    const provider = revenueCatProvider({
      ...opts,
      secretKey: "sk_test",
      fetch: (async () => new Response("down", { status: 503 })) as unknown as typeof fetch,
    });
    await expect(provider.getEntitlement("u1", now)).rejects.toThrow(/503/);
  });
});

describe("webhooks", () => {
  it("authorizes only the exact Bearer secret", () => {
    const secret = "s".repeat(40);
    expect(webhookAuthorized(`Bearer ${secret}`, secret)).toBe(true);
    expect(webhookAuthorized(secret, secret)).toBe(false);
    expect(webhookAuthorized(`Bearer ${secret}x`, secret)).toBe(false);
    expect(webhookAuthorized(undefined, secret)).toBe(false);
  });

  it("collects every customer an event touches, once", () => {
    expect(
      webhookCustomerIds({
        id: "e",
        type: "TRANSFER",
        app_user_id: "a",
        original_app_user_id: "a",
        aliases: ["a", "b"],
        transferred_from: ["c"],
        transferred_to: ["d"],
      }),
    ).toEqual(["a", "b", "c", "d"]);
  });
});
