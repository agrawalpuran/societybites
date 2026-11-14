-- Optional society scope. No rows keeps platform-wide coupons unchanged.
CREATE TABLE IF NOT EXISTS "CouponEligibleSociety" (
    "couponId" TEXT NOT NULL,
    "societyId" TEXT NOT NULL,

    CONSTRAINT "CouponEligibleSociety_pkey" PRIMARY KEY ("couponId","societyId")
);

CREATE INDEX IF NOT EXISTS "CouponEligibleSociety_societyId_idx" ON "CouponEligibleSociety"("societyId");

DO $$ BEGIN
  ALTER TABLE "CouponEligibleSociety" ADD CONSTRAINT "CouponEligibleSociety_couponId_fkey" FOREIGN KEY ("couponId") REFERENCES "Coupon"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  ALTER TABLE "CouponEligibleSociety" ADD CONSTRAINT "CouponEligibleSociety_societyId_fkey" FOREIGN KEY ("societyId") REFERENCES "Society"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;