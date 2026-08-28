-- Additive Society discovery fields. Nullable so existing rows (including
-- prestige-notting-hill) stay valid. Do not change Society IDs.
-- This file is created only — it has not been applied.

ALTER TABLE "Society" ADD COLUMN IF NOT EXISTS "googlePlaceId" TEXT;
ALTER TABLE "Society" ADD COLUMN IF NOT EXISTS "latitude" DOUBLE PRECISION;
ALTER TABLE "Society" ADD COLUMN IF NOT EXISTS "longitude" DOUBLE PRECISION;

CREATE UNIQUE INDEX IF NOT EXISTS "Society_googlePlaceId_key" ON "Society"("googlePlaceId");
