-- CreateTable
CREATE TABLE "SellerFssai" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "registrationNumber" TEXT,
    "documentStorageReference" TEXT,
    "documentType" TEXT,
    "status" TEXT NOT NULL DEFAULT 'NOT_SUBMITTED',
    "rejectionReason" TEXT,
    "submittedAt" TIMESTAMP(3),
    "reviewedAt" TIMESTAMP(3),
    "reviewedBy" TEXT,
    "needsAssistance" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SellerFssai_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FssaiAssistanceRequest" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "societyId" TEXT,
    "status" TEXT NOT NULL DEFAULT 'NEW',
    "requestedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FssaiAssistanceRequest_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SellerFssai_userId_key" ON "SellerFssai"("userId");

-- CreateIndex
CREATE INDEX "SellerFssai_status_submittedAt_idx" ON "SellerFssai"("status", "submittedAt");

-- CreateIndex
CREATE INDEX "FssaiAssistanceRequest_status_requestedAt_idx" ON "FssaiAssistanceRequest"("status", "requestedAt");

-- CreateIndex
CREATE INDEX "FssaiAssistanceRequest_userId_requestedAt_idx" ON "FssaiAssistanceRequest"("userId", "requestedAt");

-- AddForeignKey
ALTER TABLE "SellerFssai" ADD CONSTRAINT "SellerFssai_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SellerFssai" ADD CONSTRAINT "SellerFssai_reviewedBy_fkey" FOREIGN KEY ("reviewedBy") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FssaiAssistanceRequest" ADD CONSTRAINT "FssaiAssistanceRequest_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FssaiAssistanceRequest" ADD CONSTRAINT "FssaiAssistanceRequest_societyId_fkey" FOREIGN KEY ("societyId") REFERENCES "Society"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Backfill registration numbers captured on User (legacy capture-only fields).
INSERT INTO "SellerFssai" ("id", "userId", "registrationNumber", "status", "createdAt", "updatedAt")
SELECT
    (u."id" || '-fssai'),
    u."id",
    u."fssaiNumber",
    'NOT_SUBMITTED',
    NOW(),
    NOW()
FROM "User" u
WHERE u."fssaiNumber" IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM "SellerFssai" sf WHERE sf."userId" = u."id");
