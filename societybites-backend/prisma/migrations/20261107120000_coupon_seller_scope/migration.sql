-- Optional kitchen scope. Null keeps platform-wide coupons unchanged.
ALTER TABLE "Coupon" ADD COLUMN IF NOT EXISTS "sellerId" TEXT;

CREATE INDEX IF NOT EXISTS "Coupon_sellerId_idx" ON "Coupon"("sellerId");

DO $$ BEGIN
  ALTER TABLE "Coupon" ADD CONSTRAINT "Coupon_sellerId_fkey" FOREIGN KEY ("sellerId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;