-- Additive seller fulfilment preference. Existing users stay BUYER_PICKUP (current pickup-only behavior).
-- deliveryCharge uses the project's existing Float money convention.

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "fulfilmentMode" TEXT NOT NULL DEFAULT 'BUYER_PICKUP';
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "deliveryCharge" DOUBLE PRECISION NOT NULL DEFAULT 0;
