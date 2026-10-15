-- Outside-society UPI: delivery fee collected in cash (seller or delivery person).
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "outsideDeliveryCollectBy" TEXT NOT NULL DEFAULT 'seller';

ALTER TABLE "Order" ADD COLUMN IF NOT EXISTS "deliveryCollectBy" TEXT;
ALTER TABLE "Order" ADD COLUMN IF NOT EXISTS "deliveryCashConfirmedAt" TIMESTAMP(3);
