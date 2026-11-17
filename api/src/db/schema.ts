import { sql } from "drizzle-orm";
import {
  boolean,
  index,
  jsonb,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";

const createdAt = () =>
  timestamp("created_at", { withTimezone: true }).notNull().defaultNow();

/** One row per Google account that has signed in. */
export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  /** Google's stable account id (the ID token's `sub`). */
  googleSub: text("google_sub").notNull().unique(),
  email: text("email").notNull(),
  name: text("name"),
  avatarUrl: text("avatar_url"),
  createdAt: createdAt(),
  lastLoginAt: timestamp("last_login_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  /**
   * Pro granted by hand (support, promos, the developer's own account): "free"
   * or "pro". Billing never touches it, so a store sync can't wipe a grant.
   */
  plan: text("plan").notNull().default("free"),
  /** When the granted Pro ends. Null with plan "pro" means it doesn't end. */
  proExpiresAt: timestamp("pro_expires_at", { withTimezone: true }),

  // Store purchase (Google Play or the web, verified by RevenueCat). Only the billing
  // sync writes these, always from RevenueCat's server-side view of the
  // customer, never from anything the app sends. See src/billing.ts.

  /** "pro" while the purchased entitlement is active, else "free". */
  storePlan: text("store_plan").notNull().default("free"),
  /** When the purchased Pro ends (or ended). Null with "pro": a lifetime purchase. */
  storeProExpiresAt: timestamp("store_pro_expires_at", { withTimezone: true }),
  /** Store product behind the entitlement, e.g. "pro:weekly". */
  storeProductId: text("store_product_id"),
  /** False once the user cancels (Pro still runs to storeProExpiresAt). */
  storeWillRenew: boolean("store_will_renew").notNull().default(false),
  /** Renewal payment failed; the store is retrying (grace period / account hold). */
  storeBillingIssue: boolean("store_billing_issue").notNull().default(false),
  /** RevenueCat store of that purchase: "play_store", "rc_billing" (web)… */
  storeName: text("store_name"),
  /** Where the customer manages it: Google Play, or RevenueCat's web portal. */
  storeManagementUrl: text("store_management_url"),
  /** When RevenueCat was last asked about this user. */
  storeSyncedAt: timestamp("store_synced_at", { withTimezone: true }),
});

/**
 * RevenueCat webhook deliveries, for auditing ("did the renewal arrive?").
 * Not used to decide Pro: each delivery triggers a fresh read from RevenueCat.
 */
export const billingEvents = pgTable(
  "billing_events",
  {
    /** RevenueCat's event id. Redeliveries reuse it. */
    id: text("id").primaryKey(),
    type: text("type").notNull(),
    /** RevenueCat app user id, i.e. our users.id for real customers. */
    appUserId: text("app_user_id"),
    /** "PRODUCTION" or "SANDBOX". */
    environment: text("environment"),
    receivedAt: timestamp("received_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index("billing_events_app_user_idx").on(t.appUserId)],
);

/**
 * App sessions. The app holds the raw token; only its SHA-256 is stored, so a
 * database leak doesn't hand out working sessions.
 */
export const sessions = pgTable(
  "sessions",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    tokenHash: text("token_hash").notNull().unique(),
    createdAt: createdAt(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  },
  (t) => [index("sessions_user_idx").on(t.userId)],
);

/** Library folders (Pro). Names are unique per user, ignoring case. */
export const folders = pgTable(
  "folders",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    name: text("name").notNull(),
    createdAt: createdAt(),
  },
  (t) => [uniqueIndex("folders_user_name_idx").on(t.userId, sql`lower(${t.name})`)],
);

/** One swatch, stored in display order. Hex values are 6 lowercase chars, no '#'. */
export type PaletteColor = {
  hex: string;
  name: string;
  textColor: string;
};

export const palettes = pgTable(
  "palettes",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    name: text("name").notNull(),
    /** "palette" or "gradient": which generator produced it. */
    kind: text("kind").notNull().default("palette"),
    colors: jsonb("colors").$type<PaletteColor[]>().notNull(),
    /** The folder it's filed in (Pro), or null. Deleting the folder unfiles it. */
    folderId: uuid("folder_id").references(() => folders.id, { onDelete: "set null" }),
    /** Free-form labels (Pro), in the order the user added them. */
    tags: text("tags")
      .array()
      .notNull()
      .default(sql`'{}'::text[]`),
    createdAt: createdAt(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (t) => [index("palettes_user_created_idx").on(t.userId, t.createdAt)],
);

export type UserRow = typeof users.$inferSelect;
export type PaletteRow = typeof palettes.$inferSelect;
export type FolderRow = typeof folders.$inferSelect;
export type BillingEventRow = typeof billingEvents.$inferInsert;
