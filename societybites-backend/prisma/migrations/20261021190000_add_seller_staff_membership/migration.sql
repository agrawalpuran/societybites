-- CreateTable
CREATE TABLE "SellerStaffMembership" (
    "id" TEXT NOT NULL,
    "sellerUserId" TEXT NOT NULL,
    "staffUserId" TEXT NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'owner',
    "status" TEXT NOT NULL DEFAULT 'active',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SellerStaffMembership_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "SellerStaffMembership_staffUserId_status_idx" ON "SellerStaffMembership"("staffUserId", "status");

-- CreateIndex
CREATE INDEX "SellerStaffMembership_sellerUserId_status_idx" ON "SellerStaffMembership"("sellerUserId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "SellerStaffMembership_sellerUserId_staffUserId_key" ON "SellerStaffMembership"("sellerUserId", "staffUserId");

-- AddForeignKey
ALTER TABLE "SellerStaffMembership" ADD CONSTRAINT "SellerStaffMembership_sellerUserId_fkey" FOREIGN KEY ("sellerUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SellerStaffMembership" ADD CONSTRAINT "SellerStaffMembership_staffUserId_fkey" FOREIGN KEY ("staffUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
