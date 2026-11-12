-- Swappable payment provider. Null paymentProvider means checkout has not locked one yet.
ALTER TABLE "Order" ADD COLUMN "paymentProvider" TEXT;
ALTER TABLE "Order" ADD COLUMN "gatewayAmount" DOUBLE PRECISION;
ALTER TABLE "Order" ADD COLUMN "gatewayPaymentId" TEXT;
ALTER TABLE "Order" ADD COLUMN "gatewayUpiLink" TEXT;
ALTER TABLE "Order" ADD COLUMN "gatewayQrPayload" TEXT;
ALTER TABLE "Order" ADD COLUMN "splitStatus" TEXT;
ALTER TABLE "Order" ADD COLUMN "splitError" TEXT;

CREATE TABLE "SellerPayoutProfile" (
    "userId" TEXT NOT NULL,
    "pan" TEXT NOT NULL,
    "settlementMode" TEXT NOT NULL,
    "accountNumber" TEXT,
    "ifsc" TEXT,
    "accountHolder" TEXT,
    "vendorId" TEXT,
    "vendorStatus" TEXT,
    "vendorError" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SellerPayoutProfile_pkey" PRIMARY KEY ("userId")
);

CREATE UNIQUE INDEX "SellerPayoutProfile_vendorId_key" ON "SellerPayoutProfile"("vendorId");

ALTER TABLE "SellerPayoutProfile" ADD CONSTRAINT "SellerPayoutProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
