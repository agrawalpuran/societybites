-- Additive selling-reach foundation.
-- Existing User rows receive MY_SOCIETY via the column default.
-- CityReachConfig is empty until an admin sets radii (no production values invented here).

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "sellingReachLevel" TEXT NOT NULL DEFAULT 'MY_SOCIETY';

CREATE TABLE IF NOT EXISTS "CityReachConfig" (
    "cityKey" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "nearbyRadiusKm" DOUBLE PRECISION NOT NULL,
    "extendedRadiusKm" DOUBLE PRECISION NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CityReachConfig_pkey" PRIMARY KEY ("cityKey")
);
