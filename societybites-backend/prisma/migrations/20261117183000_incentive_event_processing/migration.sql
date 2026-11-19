-- AlterTable
ALTER TABLE "IncentiveEvent" ADD COLUMN "claimedAt" TIMESTAMP(3),
ADD COLUMN "claimedBy" TEXT,
ADD COLUMN "claimToken" TEXT;

-- AlterTable
ALTER TABLE "IncentiveAuditLog" ADD COLUMN "incentiveEventId" TEXT,
ADD COLUMN "attemptNumber" INTEGER;

-- CreateIndex
CREATE INDEX "IncentiveAuditLog_incentiveEventId_idx" ON "IncentiveAuditLog"("incentiveEventId");

-- AddForeignKey
ALTER TABLE "IncentiveAuditLog" ADD CONSTRAINT "IncentiveAuditLog_incentiveEventId_fkey" FOREIGN KEY ("incentiveEventId") REFERENCES "IncentiveEvent"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- One terminal incentive event per order, including concurrent inserts of different types.
CREATE UNIQUE INDEX "IncentiveEvent_one_terminal_order_event"
ON "IncentiveEvent" ("entityId")
WHERE "entityType" = 'order'
  AND "type" IN ('ORDER_QUALIFIED', 'ORDER_CANCELLED', 'ORDER_REJECTED');

-- One stored processing outcome per event, action, and attempt. Replay rows are not included.
CREATE UNIQUE INDEX "IncentiveAuditLog_processing_outcome_key"
ON "IncentiveAuditLog" ("incentiveEventId", "action", "attemptNumber")
WHERE "incentiveEventId" IS NOT NULL
  AND "action" IN ('EVENT_PROCESSED', 'EVENT_SKIPPED', 'EVENT_FAILED', 'EVENT_DEAD', 'EVENT_RECOVERED');
