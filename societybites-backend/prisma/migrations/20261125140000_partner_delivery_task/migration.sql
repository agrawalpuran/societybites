-- Partner delivery POC. Additive only. Null deliveryProvider keeps today's path.
ALTER TABLE "Order" ADD COLUMN "deliveryProvider" TEXT;

CREATE TABLE "DeliveryTask" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "state" TEXT NOT NULL,
    "externalId" TEXT,
    "lspName" TEXT,
    "riderName" TEXT,
    "riderPhone" TEXT,
    "trackingUrl" TEXT,
    "pickupOtp" TEXT,
    "dropOtp" TEXT,
    "quotedFare" DOUBLE PRECISION,
    "billedFare" DOUBLE PRECISION,
    "lastPayload" TEXT,
    "lastError" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DeliveryTask_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "DeliveryTask_orderId_key" ON "DeliveryTask"("orderId");
CREATE INDEX "DeliveryTask_externalId_idx" ON "DeliveryTask"("externalId");

ALTER TABLE "DeliveryTask" ADD CONSTRAINT "DeliveryTask_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;
