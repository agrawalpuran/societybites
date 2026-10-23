-- AlterTable
ALTER TABLE "Listing" ADD COLUMN "discountEnabled" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "discountPercent" DOUBLE PRECISION,
ADD COLUMN "discountStartsAt" TIMESTAMP(3),
ADD COLUMN "discountEndsAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "OrderItem" ADD COLUMN "originalUnitPrice" DOUBLE PRECISION,
ADD COLUMN "discountPercent" DOUBLE PRECISION;
