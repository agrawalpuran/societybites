-- CreateEnum
CREATE TYPE "CouponDiscountType" AS ENUM ('FIXED', 'PERCENTAGE');

-- CreateEnum
CREATE TYPE "CouponAudienceType" AS ENUM ('ALL', 'SELECTED_USERS');

-- CreateEnum
CREATE TYPE "CouponStatus" AS ENUM ('DRAFT', 'ACTIVE', 'PAUSED', 'EXPIRED', 'EXHAUSTED');

-- CreateEnum
CREATE TYPE "CouponFundedBy" AS ENUM ('SOCIETYEATS');

-- CreateEnum
CREATE TYPE "CouponUsageFrequency" AS ENUM ('ONCE', 'DAILY', 'WEEKLY', 'MONTHLY', 'CUSTOM');

-- CreateEnum
CREATE TYPE "CouponRedemptionStatus" AS ENUM ('APPLIED', 'REDEEMED', 'REVERSED');

-- CreateTable
CREATE TABLE "Coupon" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "discountType" "CouponDiscountType" NOT NULL,
    "discountValue" DOUBLE PRECISION NOT NULL,
    "maximumDiscount" DOUBLE PRECISION,
    "minimumOrderValue" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "validFrom" TIMESTAMP(3) NOT NULL,
    "validUntil" TIMESTAMP(3) NOT NULL,
    "totalUsageLimit" INTEGER,
    "usagePerBuyerLimit" INTEGER,
    "usageFrequency" "CouponUsageFrequency",
    "campaignBudget" DOUBLE PRECISION,
    "audienceType" "CouponAudienceType" NOT NULL DEFAULT 'ALL',
    "status" "CouponStatus" NOT NULL DEFAULT 'DRAFT',
    "fundedBy" "CouponFundedBy" NOT NULL DEFAULT 'SOCIETYEATS',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Coupon_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CouponEligibleUser" (
    "couponId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,

    CONSTRAINT "CouponEligibleUser_pkey" PRIMARY KEY ("couponId","userId")
);

-- CreateTable
CREATE TABLE "CouponRedemption" (
    "id" TEXT NOT NULL,
    "couponId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "orderId" TEXT,
    "discountAmount" DOUBLE PRECISION NOT NULL,
    "status" "CouponRedemptionStatus" NOT NULL DEFAULT 'APPLIED',
    "appliedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "redeemedAt" TIMESTAMP(3),
    "reversedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CouponRedemption_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Coupon_code_key" ON "Coupon"("code");

-- CreateIndex
CREATE INDEX "Coupon_status_validUntil_idx" ON "Coupon"("status", "validUntil");

-- CreateIndex
CREATE INDEX "CouponEligibleUser_userId_idx" ON "CouponEligibleUser"("userId");

-- CreateIndex
CREATE INDEX "CouponRedemption_couponId_userId_status_idx" ON "CouponRedemption"("couponId", "userId", "status");

-- CreateIndex
CREATE INDEX "CouponRedemption_couponId_status_idx" ON "CouponRedemption"("couponId", "status");

-- CreateIndex
CREATE INDEX "CouponRedemption_orderId_idx" ON "CouponRedemption"("orderId");

-- One APPLIED or REDEEMED coupon per order. REVERSED rows do not occupy the slot.
CREATE UNIQUE INDEX "CouponRedemption_one_active_per_order" ON "CouponRedemption"("orderId") WHERE "orderId" IS NOT NULL AND "status" IN ('APPLIED', 'REDEEMED');

-- AddForeignKey
ALTER TABLE "CouponEligibleUser" ADD CONSTRAINT "CouponEligibleUser_couponId_fkey" FOREIGN KEY ("couponId") REFERENCES "Coupon"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CouponEligibleUser" ADD CONSTRAINT "CouponEligibleUser_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CouponRedemption" ADD CONSTRAINT "CouponRedemption_couponId_fkey" FOREIGN KEY ("couponId") REFERENCES "Coupon"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CouponRedemption" ADD CONSTRAINT "CouponRedemption_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CouponRedemption" ADD CONSTRAINT "CouponRedemption_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE SET NULL ON UPDATE CASCADE;
