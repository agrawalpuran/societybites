-- Link campaign product copies to the catalog listing they were copied from.
-- Historical copies stay NULL and remain orderable; protection uses this ID, not name.

ALTER TABLE "Listing" ADD COLUMN IF NOT EXISTS "sourceListingId" TEXT;

CREATE INDEX IF NOT EXISTS "Listing_sourceListingId_idx" ON "Listing"("sourceListingId");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'Listing_sourceListingId_fkey'
  ) THEN
    ALTER TABLE "Listing"
      ADD CONSTRAINT "Listing_sourceListingId_fkey"
      FOREIGN KEY ("sourceListingId") REFERENCES "Listing"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;
