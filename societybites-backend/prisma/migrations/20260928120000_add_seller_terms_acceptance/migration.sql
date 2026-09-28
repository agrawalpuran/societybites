-- Seller terms acceptance. Existing sellers are not backfilled and are not blocked.

CREATE TABLE IF NOT EXISTS "SellerTermsAcceptance" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "termsVersion" TEXT NOT NULL,
    "acceptedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SellerTermsAcceptance_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "SellerTermsAcceptance_userId_termsVersion_key"
    ON "SellerTermsAcceptance"("userId", "termsVersion");

CREATE INDEX IF NOT EXISTS "SellerTermsAcceptance_userId_idx"
    ON "SellerTermsAcceptance"("userId");

DO $$ BEGIN
  ALTER TABLE "SellerTermsAcceptance"
    ADD CONSTRAINT "SellerTermsAcceptance_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
