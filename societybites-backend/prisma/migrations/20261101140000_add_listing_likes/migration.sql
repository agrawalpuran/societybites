-- One like per buyer per dish. Variant sizes share dishKey.
CREATE TABLE "ListingLike" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "dishKey" TEXT NOT NULL,
    "listingId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ListingLike_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ListingLike_userId_dishKey_key" ON "ListingLike"("userId", "dishKey");
CREATE INDEX "ListingLike_dishKey_idx" ON "ListingLike"("dishKey");

ALTER TABLE "ListingLike" ADD CONSTRAINT "ListingLike_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
