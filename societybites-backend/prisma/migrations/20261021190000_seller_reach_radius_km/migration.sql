-- Seller-chosen reach radius (km) when selling beyond own society.
ALTER TABLE "User" ADD COLUMN "sellingReachRadiusKm" DOUBLE PRECISION;

-- Max km allowed on the seller reach slider for this city (super admin).
ALTER TABLE "CityReachConfig" ADD COLUMN "maxSellerRadiusKm" DOUBLE PRECISION NOT NULL DEFAULT 10;
