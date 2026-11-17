CREATE TABLE "billing_events" (
	"id" text PRIMARY KEY NOT NULL,
	"type" text NOT NULL,
	"app_user_id" text,
	"environment" text,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "store_plan" text DEFAULT 'free' NOT NULL;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "store_pro_expires_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "store_product_id" text;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "store_will_renew" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "store_billing_issue" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "store_synced_at" timestamp with time zone;--> statement-breakpoint
CREATE INDEX "billing_events_app_user_idx" ON "billing_events" USING btree ("app_user_id");