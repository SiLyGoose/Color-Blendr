import type { UserRow } from "./db/schema";

/** Palettes a free account can keep in its library. Pro is unlimited. */
export const FREE_PALETTE_LIMIT = 10;

/** Upper bound on folders per account, so lists stay small. */
export const MAX_FOLDERS = 100;

/** The columns that decide the plan: a hand grant and a store purchase. */
export type PlanFields = Pick<
  UserRow,
  "plan" | "proExpiresAt" | "storePlan" | "storeProExpiresAt"
>;

/** A grant is active when it's "pro" and hasn't ended (null: never ends). */
function grantActive(plan: string, endsAt: Date | null, now: Date): boolean {
  return plan === "pro" && (endsAt === null || endsAt > now);
}

/** Pro by hand grant (support) or by a store purchase. */
export function isPro(user: PlanFields, now: Date): boolean {
  return (
    grantActive(user.plan, user.proExpiresAt, now) ||
    grantActive(user.storePlan, user.storeProExpiresAt, now)
  );
}

/** True if the store purchase alone gives Pro right now. */
export function hasStorePro(user: PlanFields, now: Date): boolean {
  return grantActive(user.storePlan, user.storeProExpiresAt, now);
}

/**
 * When Pro ends: the later of the active grants. Null when free, or when an
 * active grant never ends.
 */
export function proEndsAt(user: PlanFields, now: Date): Date | null {
  const ends: Date[] = [];
  for (const [plan, endsAt] of [
    [user.plan, user.proExpiresAt],
    [user.storePlan, user.storeProExpiresAt],
  ] as const) {
    if (!grantActive(plan, endsAt, now)) continue;
    if (endsAt === null) return null;
    ends.push(endsAt);
  }
  if (ends.length === 0) return null;
  return new Date(Math.max(...ends.map((d) => d.getTime())));
}

/** How many palettes this account may keep, or null for no limit. */
export function paletteLimit(user: PlanFields, now: Date): number | null {
  return isPro(user, now) ? null : FREE_PALETTE_LIMIT;
}
