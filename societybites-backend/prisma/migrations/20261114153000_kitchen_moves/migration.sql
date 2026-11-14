CREATE TABLE "KitchenMove" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "fromSocietyId" TEXT NOT NULL,
    "fromFlatId" TEXT,
    "toSocietyId" TEXT NOT NULL,
    "toFlatId" TEXT,
    "toBlock" TEXT,
    "toFlatNumber" TEXT,
    "addressProofUrl" TEXT NOT NULL,
    "addressProofStatus" TEXT NOT NULL DEFAULT 'PENDING',
    "addressProofReviewedAt" TIMESTAMP(3),
    "addressProofReviewedBy" TEXT,
    "fssaiRegistrationNumber" TEXT,
    "fssaiRegisteredName" TEXT,
    "fssaiLicenceExpiry" TIMESTAMP(3),
    "fssaiDocumentStorageReference" TEXT,
    "fssaiDocumentType" TEXT,
    "fssaiStatus" TEXT NOT NULL DEFAULT 'NOT_SUBMITTED',
    "fssaiRejectionReason" TEXT,
    "fssaiReviewedAt" TIMESTAMP(3),
    "fssaiReviewedBy" TEXT,
    "rejectionReason" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "reviewedBy" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "KitchenMove_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "KitchenMove_status_createdAt_idx" ON "KitchenMove"("status", "createdAt");

CREATE INDEX "KitchenMove_userId_status_idx" ON "KitchenMove"("userId", "status");

ALTER TABLE "KitchenMove" ADD CONSTRAINT "KitchenMove_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "KitchenMove" ADD CONSTRAINT "KitchenMove_fromSocietyId_fkey" FOREIGN KEY ("fromSocietyId") REFERENCES "Society"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "KitchenMove" ADD CONSTRAINT "KitchenMove_toSocietyId_fkey" FOREIGN KEY ("toSocietyId") REFERENCES "Society"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "KitchenMove" ADD CONSTRAINT "KitchenMove_toFlatId_fkey" FOREIGN KEY ("toFlatId") REFERENCES "Flat"("id") ON DELETE SET NULL ON UPDATE CASCADE;
