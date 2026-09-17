-- Classify listings as REGULAR (marketplace) or PREORDER (seller pre-order catalog).
-- Existing rows stay REGULAR so current Home / storefront / nearby behaviour is unchanged.

ALTER TABLE "Listing" ADD COLUMN IF NOT EXISTS "catalogType" TEXT NOT NULL DEFAULT 'REGULAR';
