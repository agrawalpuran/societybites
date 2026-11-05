-- Seller UPI account type: PERSONAL (default, copy/open app) or MERCHANT (collect intent).

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "upiAccountType" TEXT NOT NULL DEFAULT 'PERSONAL';
