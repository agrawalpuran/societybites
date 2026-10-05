-- CreateTable
CREATE TABLE "IssueReport" (
    "id" TEXT NOT NULL,
    "issueNumber" SERIAL NOT NULL,
    "reference" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "userRole" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "orderId" TEXT,
    "listingId" TEXT,
    "sellerId" TEXT,
    "status" TEXT NOT NULL DEFAULT 'OPEN',
    "adminResponse" TEXT,
    "platform" TEXT,
    "appVersion" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "resolvedAt" TIMESTAMP(3),

    CONSTRAINT "IssueReport_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "IssueReport_issueNumber_key" ON "IssueReport"("issueNumber");

-- CreateIndex
CREATE UNIQUE INDEX "IssueReport_reference_key" ON "IssueReport"("reference");

-- CreateIndex
CREATE INDEX "IssueReport_userId_createdAt_idx" ON "IssueReport"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "IssueReport_status_createdAt_idx" ON "IssueReport"("status", "createdAt");

-- AddForeignKey
ALTER TABLE "IssueReport" ADD CONSTRAINT "IssueReport_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Human-readable references start at SE-1001.
ALTER SEQUENCE "IssueReport_issueNumber_seq" RESTART WITH 1001;
