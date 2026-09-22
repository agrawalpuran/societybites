-- AlterTable
ALTER TABLE "Listing" ADD COLUMN "availabilityMode" TEXT NOT NULL DEFAULT 'READY_NOW';
ALTER TABLE "Listing" ADD COLUMN "preparationTimeMinutes" INTEGER;
ALTER TABLE "Listing" ADD COLUMN "maxDailyOrders" INTEGER;
