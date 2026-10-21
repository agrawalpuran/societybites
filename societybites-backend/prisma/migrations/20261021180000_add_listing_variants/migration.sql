-- AlterTable
ALTER TABLE "Listing" ADD COLUMN "variantGroupId" TEXT,
ADD COLUMN "variantLabel" TEXT;

-- CreateIndex
CREATE INDEX "Listing_variantGroupId_idx" ON "Listing"("variantGroupId");
