-- Payment reminder cooldown for seller-initiated buyer nudges.
ALTER TABLE "Order" ADD COLUMN "lastPaymentReminderAt" TIMESTAMP(3);
