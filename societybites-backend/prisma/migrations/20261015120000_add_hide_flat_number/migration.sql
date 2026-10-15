-- Seller privacy: hide flat number on public surfaces (default off for existing sellers).
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "hideFlatNumber" BOOLEAN NOT NULL DEFAULT false;
