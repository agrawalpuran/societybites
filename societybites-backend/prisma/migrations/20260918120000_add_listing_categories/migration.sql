-- AlterTable
ALTER TABLE "Listing" ADD COLUMN "categories" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

UPDATE "Listing"
SET "categories" = ARRAY["category"]
WHERE "category" IS NOT NULL
  AND btrim("category") <> ''
  AND cardinality("categories") = 0;
