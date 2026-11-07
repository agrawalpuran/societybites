-- AlterTable
ALTER TABLE "User" ADD COLUMN "storefrontSlug" TEXT,
ADD COLUMN "storefrontAccentColor" TEXT,
ADD COLUMN "storefrontBannerUrl" TEXT,
ADD COLUMN "storefrontTagline" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "User_storefrontSlug_key" ON "User"("storefrontSlug");
