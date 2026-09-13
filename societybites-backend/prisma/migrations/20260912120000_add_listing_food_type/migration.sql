-- Additive Listing.foodType. Nullable so existing rows stay valid.
-- Values: VEG | NON_VEG. Do not change Listing IDs.

ALTER TABLE "Listing" ADD COLUMN IF NOT EXISTS "foodType" TEXT;
