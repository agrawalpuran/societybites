-- Additive seller payment preference.
-- Default UPI_AND_COD matches current checkout (UPI + cash) so existing sellers keep COD.

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "paymentPreference" TEXT NOT NULL DEFAULT 'UPI_AND_COD';
