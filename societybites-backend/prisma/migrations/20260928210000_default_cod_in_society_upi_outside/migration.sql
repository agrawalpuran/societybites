-- New sellers default to COD in society and UPI outside.
-- Existing rows keep whatever they already saved.

ALTER TABLE "User"
  ALTER COLUMN "paymentPreference" SET DEFAULT 'COD_IN_SOCIETY_UPI_OUTSIDE';
