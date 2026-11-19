-- Phase 2D-4. Additive and unapplied until the owner names the database.
-- Null for drafts and for listings published before this column existed.

ALTER TABLE "Listing" ADD COLUMN "firstPublishedAt" TIMESTAMP(3);
