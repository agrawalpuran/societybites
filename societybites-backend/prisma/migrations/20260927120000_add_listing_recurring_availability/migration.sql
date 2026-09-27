-- AlterTable
ALTER TABLE "Listing" ADD COLUMN "recurringEnabled" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Listing" ADD COLUMN "recurringWeekdays" INTEGER[] DEFAULT ARRAY[]::INTEGER[];
ALTER TABLE "Listing" ADD COLUMN "recurringStartMinute" INTEGER;
ALTER TABLE "Listing" ADD COLUMN "recurringEndMinute" INTEGER;
ALTER TABLE "Listing" ADD COLUMN "recurringDailyLimit" INTEGER;
