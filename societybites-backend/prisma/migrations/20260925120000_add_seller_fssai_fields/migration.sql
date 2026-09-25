-- Additive FSSAI capture on sellers. Nullable so existing users are unchanged.

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "fssaiNumber" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "fssaiExpiry" TIMESTAMP(3);
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "fssaiRegisteredName" TEXT;
