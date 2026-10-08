-- CreateTable
CREATE TABLE "OrderIdempotency" (
    "id" TEXT NOT NULL,
    "buyerId" TEXT NOT NULL,
    "idempotencyKey" TEXT NOT NULL,
    "orderId" TEXT,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "OrderIdempotency_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "OrderIdempotency_buyerId_idempotencyKey_key" ON "OrderIdempotency"("buyerId", "idempotencyKey");

-- CreateIndex
CREATE UNIQUE INDEX "OrderIdempotency_orderId_key" ON "OrderIdempotency"("orderId");

-- CreateIndex
CREATE INDEX "OrderIdempotency_buyerId_idx" ON "OrderIdempotency"("buyerId");

-- AddForeignKey
ALTER TABLE "OrderIdempotency" ADD CONSTRAINT "OrderIdempotency_buyerId_fkey" FOREIGN KEY ("buyerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OrderIdempotency" ADD CONSTRAINT "OrderIdempotency_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE SET NULL ON UPDATE CASCADE;
