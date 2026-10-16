-- CreateTable
CREATE TABLE "FestivalBanner" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "title" TEXT,
    "subtitle" TEXT,
    "imageUrl" TEXT,
    "placement" TEXT NOT NULL DEFAULT 'BELOW_SEARCH',
    "status" TEXT NOT NULL DEFAULT 'DRAFT',
    "startsAt" TIMESTAMP(3),
    "endsAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FestivalBanner_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "FestivalBanner_status_startsAt_endsAt_idx" ON "FestivalBanner"("status", "startsAt", "endsAt");
