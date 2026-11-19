-- Phase 2D-1. Additive and unapplied until the owner names the database.
-- Nullable so existing referral-code rows stay valid. No foreign key.

ALTER TABLE "IncentiveReferralCode" ADD COLUMN "expiresAt" TIMESTAMP(3),
ADD COLUMN "campaignVersionId" TEXT;
