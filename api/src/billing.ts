// Store billing through RevenueCat.
//
// Trust model (see docs/monetization.md):
// - The app never tells the API that a user has paid. It buys through Google
//   Play Billing with the RevenueCat SDK, RevenueCat validates the purchase
//   token with Google's servers, and the API then asks RevenueCat (with the
//   secret key, which never ships in the app) what the customer owns.
// - Webhooks only say "something changed for this customer". The handler
//   re-reads the customer from RevenueCat instead of trusting the payload, so a
//   forged or replayed webhook can't grant anything, and late or out-of-order
//   deliveries can't leave stale state behind.

import { createHash, timingSafeEqual } from "node:crypto";
import { z } from "zod";

/** What a store purchase currently gives a user, as stored on users.store_*. */
export type StoreEntitlement = {
  /** "pro" while the entitlement is active. */
  plan: "free" | "pro";
  /** When it ends or ended. Null with "pro": lifetime. Null with "free": never bought. */
  expiresAt: Date | null;
  productId: string | null;
  willRenew: boolean;
  billingIssue: boolean;
};

export const NO_ENTITLEMENT: StoreEntitlement = {
  plan: "free",
  expiresAt: null,
  productId: null,
  willRenew: false,
  billingIssue: false,
};

/** Per-customer rules for reading an entitlement. */
export type EntitlementContext = {
  /**
   * A developer test account (REVENUECAT_TESTER_EMAILS): its sandbox
   * purchases count from any store, including RevenueCat's Test Store.
   */
  tester?: boolean;
};

export interface BillingProvider {
  /** The customer's Pro entitlement, read server-side from RevenueCat. */
  getEntitlement(
    appUserId: string,
    now: Date,
    context?: EntitlementContext,
  ): Promise<StoreEntitlement>;
  /** Removes the customer's data from RevenueCat (account deletion). */
  deleteCustomer(appUserId: string): Promise<void>;
}

// ---------------------------------------------------------------------------
// RevenueCat REST API v1: GET /v1/subscribers/{app_user_id}
// https://www.revenuecat.com/docs/api-v1
// ---------------------------------------------------------------------------

const isoDate = z.string().nullish();

const subscriberResponse = z.object({
  subscriber: z.object({
    entitlements: z
      .record(
        z.string(),
        z.object({
          expires_date: isoDate,
          grace_period_expires_date: isoDate,
          product_identifier: z.string().nullish(),
        }),
      )
      .default({}),
    subscriptions: z
      .record(
        z.string(),
        z.object({
          store: z.string().nullish(),
          is_sandbox: z.boolean().nullish(),
          unsubscribe_detected_at: isoDate,
          billing_issues_detected_at: isoDate,
          refunded_at: isoDate,
        }),
      )
      .default({}),
    non_subscriptions: z
      .record(
        z.string(),
        z.array(z.object({ store: z.string().nullish(), is_sandbox: z.boolean().nullish() })),
      )
      .default({}),
  }),
});

export type RevenueCatSubscriber = z.input<typeof subscriberResponse>;

export type RevenueCatOptions = {
  /** Secret API key (sk_…). Server only: it can read and change any customer. */
  secretKey: string;
  /** The RevenueCat entitlement that means Pro. */
  entitlementId: string;
  /**
   * Count sandbox (test) purchases. On Google Play only license testers listed
   * in Play Console can make them, so this is safe there. Keep it false for
   * stores where anyone can get sandbox access (e.g. iOS TestFlight).
   */
  allowSandbox: boolean;
  /**
   * Stores whose purchases count. "promotional" is a grant made from the
   * RevenueCat dashboard. Anything else (e.g. RevenueCat's Test Store, which
   * debug builds can buy from for free) is ignored.
   */
  allowedStores: readonly string[];
  fetch?: typeof fetch;
  baseUrl?: string;
};

const parseDate = (s: string | null | undefined) => {
  if (!s) return null;
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? null : d;
};

/** Turns a RevenueCat subscriber into our entitlement. Exported for tests. */
export function entitlementFromSubscriber(
  body: unknown,
  now: Date,
  opts: Pick<RevenueCatOptions, "entitlementId" | "allowSandbox" | "allowedStores">,
  context: EntitlementContext = {},
): StoreEntitlement {
  const { subscriber } = subscriberResponse.parse(body);
  const ent = subscriber.entitlements[opts.entitlementId];
  if (!ent) return NO_ENTITLEMENT;

  const productId = ent.product_identifier ?? null;
  const sub = productId ? subscriber.subscriptions[productId] : undefined;
  const oneTime = productId ? subscriber.non_subscriptions[productId] : undefined;

  // Where did the purchase come from? Unknown origin doesn't count, except
  // test purchases on a tester's own account.
  const store = sub?.store ?? oneTime?.at(-1)?.store ?? null;
  const sandbox = sub?.is_sandbox ?? oneTime?.some((p) => p.is_sandbox === true) ?? false;
  const testerTest = context.tester === true && sandbox;
  if (!testerTest) {
    const refused =
      store === null || !opts.allowedStores.includes(store)
        ? `store ${store ?? "unknown"} not allowed`
        : sandbox && !opts.allowSandbox
          ? "sandbox purchases not allowed"
          : null;
    if (refused) {
      // Logged so a misconfigured store or tester list is easy to spot.
      console.warn(`Ignoring "${opts.entitlementId}" entitlement (${productId}): ${refused}`);
      return NO_ENTITLEMENT;
    }
  }

  const lifetime = ent.expires_date == null;
  // During a billing grace period Pro keeps going until the grace period ends.
  const ends = [parseDate(ent.expires_date), parseDate(ent.grace_period_expires_date)].filter(
    (d): d is Date => d !== null,
  );
  const expiresAt = lifetime
    ? null
    : ends.length > 0
      ? new Date(Math.max(...ends.map((d) => d.getTime())))
      : null;
  if (!lifetime && expiresAt === null) return NO_ENTITLEMENT; // unparseable date

  const active = lifetime || (expiresAt !== null && expiresAt > now);
  return {
    plan: active ? "pro" : "free",
    expiresAt,
    productId,
    willRenew: !!sub && !sub.unsubscribe_detected_at && !sub.refunded_at && active,
    billingIssue: !!sub?.billing_issues_detected_at && active,
  };
}

export function revenueCatProvider(opts: RevenueCatOptions): BillingProvider {
  const doFetch = opts.fetch ?? fetch;
  const base = opts.baseUrl ?? "https://api.revenuecat.com";
  const headers = {
    authorization: `Bearer ${opts.secretKey}`,
    accept: "application/json",
  };
  const url = (appUserId: string) => `${base}/v1/subscribers/${encodeURIComponent(appUserId)}`;

  return {
    async getEntitlement(appUserId, now, context) {
      const res = await doFetch(url(appUserId), {
        headers,
        signal: AbortSignal.timeout(10_000),
      });
      if (!res.ok) {
        // Throwing (not "free") so a RevenueCat outage never strips Pro.
        throw new Error(`RevenueCat GET subscriber failed: ${res.status}`);
      }
      return entitlementFromSubscriber(await res.json(), now, opts, context);
    },

    async deleteCustomer(appUserId) {
      const res = await doFetch(url(appUserId), {
        method: "DELETE",
        headers,
        signal: AbortSignal.timeout(10_000),
      });
      if (!res.ok && res.status !== 404) {
        throw new Error(`RevenueCat DELETE subscriber failed: ${res.status}`);
      }
    },
  };
}

// ---------------------------------------------------------------------------
// Webhooks: https://www.revenuecat.com/docs/integrations/webhooks
// ---------------------------------------------------------------------------

const ref = z.string().max(200);

/** The fields we read. Everything else in the payload is ignored on purpose. */
export const revenueCatWebhook = z.object({
  event: z.object({
    id: ref,
    type: z.string().max(100),
    environment: z.string().max(20).nullish(),
    app_user_id: ref.nullish(),
    original_app_user_id: ref.nullish(),
    aliases: z.array(ref).max(100).nullish(),
    transferred_from: z.array(ref).max(100).nullish(),
    transferred_to: z.array(ref).max(100).nullish(),
  }),
});

export type RevenueCatWebhook = z.output<typeof revenueCatWebhook>;

/** Every customer id an event touches (a TRANSFER moves Pro between two). */
export function webhookCustomerIds(event: RevenueCatWebhook["event"]): string[] {
  const ids = [
    event.app_user_id,
    event.original_app_user_id,
    ...(event.aliases ?? []),
    ...(event.transferred_from ?? []),
    ...(event.transferred_to ?? []),
  ].filter((id): id is string => typeof id === "string" && id.length > 0);
  return [...new Set(ids)];
}

const sha256 = (s: string) => createHash("sha256").update(s).digest();

/**
 * Checks the webhook's Authorization header against the shared secret, in
 * constant time. RevenueCat sends the header value set in its dashboard,
 * which must be exactly `Bearer <secret>`.
 */
export function webhookAuthorized(header: string | undefined, secret: string): boolean {
  if (!header) return false;
  return timingSafeEqual(sha256(header), sha256(`Bearer ${secret}`));
}
