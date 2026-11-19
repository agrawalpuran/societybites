-- Phase 2D-2 and 2D-3. Additive and unapplied until the owner names the database.
-- No foreign keys to User, Order, or Listing. The user check is enforced in the database.

ALTER TABLE "IncentiveReferral" ADD COLUMN "campaignVersionId" TEXT,
ADD COLUMN "sellerEnabledAt" TIMESTAMP(3),
ADD COLUMN "listingId" TEXT,
ADD COLUMN "listingPublishedAt" TIMESTAMP(3),
ADD COLUMN "qualifyingOrderId" TEXT,
ADD COLUMN "qualifyingOrderAt" TIMESTAMP(3),
ADD COLUMN "qualifiedAt" TIMESTAMP(3),
ADD COLUMN "disqualifyReason" TEXT;

ALTER TABLE "IncentiveReferral" ADD CONSTRAINT "IncentiveReferral_users_distinct"
CHECK ("referrerUserId" <> "referredUserId");

CREATE INDEX "IncentiveReferral_referrer_version_kind_idx"
ON "IncentiveReferral" ("referrerUserId", "campaignVersionId", "acquisitionKind");
