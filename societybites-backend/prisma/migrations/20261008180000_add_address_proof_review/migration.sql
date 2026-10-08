-- AlterTable
ALTER TABLE "User" ADD COLUMN "addressProofStatus" TEXT;
ALTER TABLE "User" ADD COLUMN "addressProofReviewedAt" TIMESTAMP(3);
ALTER TABLE "User" ADD COLUMN "addressProofReviewedBy" TEXT;
