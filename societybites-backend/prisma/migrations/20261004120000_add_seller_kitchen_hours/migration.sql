-- Optional daily kitchen window. Both null keeps existing sellers always open.

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "kitchenOpensAt" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "kitchenClosesAt" TEXT;
