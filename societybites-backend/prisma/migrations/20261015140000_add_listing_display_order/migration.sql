-- Seller-defined catalog order for REGULAR storefront listings (nullable for legacy rows).
ALTER TABLE "Listing" ADD COLUMN IF NOT EXISTS "displayOrder" INTEGER;

CREATE INDEX IF NOT EXISTS "Listing_sellerId_displayOrder_idx" ON "Listing"("sellerId", "displayOrder");
