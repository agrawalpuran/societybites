-- Per-reach seller delivery charges. Existing single deliveryCharge is copied
-- to nearby and extended so current outside-society orders keep the same fee.
-- In-society stays 0 unless the seller sets it.

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "deliveryChargeInSociety" DOUBLE PRECISION NOT NULL DEFAULT 0;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "deliveryChargeNearby" DOUBLE PRECISION NOT NULL DEFAULT 0;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "deliveryChargeExtended" DOUBLE PRECISION NOT NULL DEFAULT 0;

UPDATE "User"
SET
  "deliveryChargeNearby" = COALESCE("deliveryCharge", 0),
  "deliveryChargeExtended" = COALESCE("deliveryCharge", 0)
WHERE "deliveryChargeNearby" = 0 AND "deliveryChargeExtended" = 0;
