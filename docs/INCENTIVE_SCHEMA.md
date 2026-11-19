# Incentive schema scripts

These six files are the SQL that creates the referral and incentive tables, adds `Listing.firstPublishedAt`, and installs the ledger guard. The copies below match the files on `feature/incentive-referral-engine`. Run the files, in this order, only on a database the owner names.

Do not run them against the hosted database. That database was not changed. `main` does not contain these scripts.

The local test database `127.0.0.1:5432/societybites_incentive_integration_v2` already has these tables, the listing column, and the three ledger triggers. Do not run the scripts there again. `CREATE TABLE` and `ADD COLUMN` are not written to be repeated. `_prisma_migrations` is absent on that database, so Prisma does not record that the files were applied.

`npm start` runs `prisma migrate deploy`. `npm run dev` does not. Starting the API does not apply this page.

## Run order

| Order | File | What it does |
|---|---|---|
| 1 | `societybites-backend/prisma/migrations/20261117120000_incentive_engine_foundation/migration.sql` | Creates the incentive tables, indexes, and foreign keys inside the incentive tables |
| 2 | `societybites-backend/prisma/migrations/20261117183000_incentive_event_processing/migration.sql` | Adds event claim columns, the audit link, and the two partial unique indexes |
| 3 | `societybites-backend/prisma/migrations/20261117203000_incentive_referral_code_pin/migration.sql` | Adds nullable `expiresAt` and `campaignVersionId` on `IncentiveReferralCode` |
| 4 | `societybites-backend/prisma/migrations/20261117213000_incentive_referral_attribution/migration.sql` | Adds referral milestone columns and the distinct-user check |
| 5 | `societybites-backend/prisma/migrations/20261117223000_listing_first_published_at/migration.sql` | Adds nullable `Listing.firstPublishedAt` |
| 6 | `societybites-backend/prisma/migrations/20261117233000_incentive_ledger_guard/migration.sql` | Makes `IncentiveLedgerEntry` append-only and checks the balance on insert |

Incentive tables have no foreign key to `User`, `Order`, `Listing`, `Coupon`, or `AppSetting`. `Listing.firstPublishedAt` is the only change to an existing product table. Money columns are `DECIMAL(12,2)`.

## 1. Foundation

```sql
-- CreateTable
CREATE TABLE "IncentiveSetting" (
    "key" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "IncentiveSetting_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "IncentiveCampaign" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "category" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'DRAFT',
    "priority" INTEGER NOT NULL DEFAULT 0,
    "stackingMode" TEXT NOT NULL DEFAULT 'STACK',
    "startsAt" TIMESTAMP(3),
    "endsAt" TIMESTAMP(3),
    "currentVersionId" TEXT,
    "createdBy" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "IncentiveCampaign_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IncentiveCampaignVersion" (
    "id" TEXT NOT NULL,
    "campaignId" TEXT NOT NULL,
    "versionNumber" INTEGER NOT NULL,
    "snapshot" JSONB NOT NULL,
    "publishedAt" TIMESTAMP(3),
    "publishedBy" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "IncentiveCampaignVersion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IncentiveAudience" (
    "id" TEXT NOT NULL,
    "versionId" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "payload" JSONB NOT NULL DEFAULT '{}',

    CONSTRAINT "IncentiveAudience_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IncentiveTrigger" (
    "id" TEXT NOT NULL,
    "versionId" TEXT NOT NULL,
    "eventType" TEXT NOT NULL,

    CONSTRAINT "IncentiveTrigger_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IncentiveRule" (
    "id" TEXT NOT NULL,
    "versionId" TEXT NOT NULL,
    "groupKey" TEXT NOT NULL,
    "parentGroupKey" TEXT,
    "combinator" TEXT,
    "field" TEXT,
    "operator" TEXT,
    "value" JSONB,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "IncentiveRule_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IncentiveRewardDefinition" (
    "id" TEXT NOT NULL,
    "versionId" TEXT NOT NULL,
    "slot" TEXT NOT NULL,
    "recipientRole" TEXT NOT NULL,
    "rewardType" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "maxDiscount" DECIMAL(12,2),
    "minOrder" DECIMAL(12,2),
    "expiryDays" INTEGER,
    "usageLimit" INTEGER,
    "stackingMode" TEXT,
    "config" JSONB NOT NULL DEFAULT '{}',

    CONSTRAINT "IncentiveRewardDefinition_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IncentiveBudget" (
    "id" TEXT NOT NULL,
    "versionId" TEXT NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'INR',
    "amountCap" DECIMAL(12,2) NOT NULL,
    "issuedAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,

    CONSTRAINT "IncentiveBudget_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IncentiveEvent" (
    "id" TEXT NOT NULL,
    "eventId" TEXT NOT NULL,
    "schemaVersion" INTEGER NOT NULL DEFAULT 1,
    "type" TEXT NOT NULL,
    "entityType" TEXT NOT NULL,
    "entityId" TEXT NOT NULL,
    "userId" TEXT,
    "occurredAt" TIMESTAMP(3) NOT NULL,
    "payload" JSONB NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "nextAttemptAt" TIMESTAMP(3),
    "lastError" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "processedAt" TIMESTAMP(3),

    CONSTRAINT "IncentiveEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IncentiveReferralCode" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "audience" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "campaignId" TEXT,
    "scopeKey" TEXT NOT NULL DEFAULT 'default',
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "IncentiveReferralCode_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IncentiveReferral" (
    "id" TEXT NOT NULL,
    "codeId" TEXT NOT NULL,
    "campaignId" TEXT,
    "referrerUserId" TEXT NOT NULL,
    "referredUserId" TEXT NOT NULL,
    "acquisitionKind" TEXT NOT NULL,
    "channel" TEXT,
    "attributedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "windowEndsAt" TIMESTAMP(3),
    "status" TEXT NOT NULL DEFAULT 'ATTRIBUTED',

    CONSTRAINT "IncentiveReferral_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IncentiveReward" (
    "id" TEXT NOT NULL,
    "campaignVersionId" TEXT NOT NULL,
    "rewardSlot" TEXT NOT NULL,
    "recipientUserId" TEXT NOT NULL,
    "sourceEventId" TEXT NOT NULL,
    "referralId" TEXT,
    "couponId" TEXT,
    "status" TEXT NOT NULL DEFAULT 'CREATED',
    "amount" DECIMAL(12,2) NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'INR',
    "expiresAt" TIMESTAMP(3),
    "idempotencyKey" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "IncentiveReward_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IncentiveLedgerEntry" (
    "id" TEXT NOT NULL,
    "rewardId" TEXT NOT NULL,
    "entryType" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'INR',
    "actorId" TEXT,
    "reason" TEXT,
    "idempotencyKey" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "IncentiveLedgerEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IncentiveRedemption" (
    "id" TEXT NOT NULL,
    "rewardId" TEXT NOT NULL,
    "orderId" TEXT,
    "amount" DECIMAL(12,2) NOT NULL,
    "status" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "IncentiveRedemption_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IncentiveRiskEvaluation" (
    "id" TEXT NOT NULL,
    "subjectType" TEXT NOT NULL,
    "subjectId" TEXT NOT NULL,
    "score" INTEGER,
    "signals" JSONB NOT NULL,
    "decision" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "IncentiveRiskEvaluation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IncentiveApproval" (
    "id" TEXT NOT NULL,
    "rewardId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "requestedBy" TEXT NOT NULL,
    "decidedBy" TEXT,
    "decision" TEXT NOT NULL,
    "reason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "IncentiveApproval_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IncentiveAuditLog" (
    "id" TEXT NOT NULL,
    "actorId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "campaignId" TEXT,
    "before" JSONB,
    "after" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "IncentiveAuditLog_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "IncentiveCampaign_status_startsAt_idx" ON "IncentiveCampaign"("status", "startsAt");

-- CreateIndex
CREATE INDEX "IncentiveCampaign_category_idx" ON "IncentiveCampaign"("category");

-- CreateIndex
CREATE INDEX "IncentiveCampaignVersion_campaignId_idx" ON "IncentiveCampaignVersion"("campaignId");

-- CreateIndex
CREATE UNIQUE INDEX "IncentiveCampaignVersion_campaignId_versionNumber_key" ON "IncentiveCampaignVersion"("campaignId", "versionNumber");

-- CreateIndex
CREATE INDEX "IncentiveAudience_versionId_idx" ON "IncentiveAudience"("versionId");

-- CreateIndex
CREATE INDEX "IncentiveTrigger_eventType_idx" ON "IncentiveTrigger"("eventType");

-- CreateIndex
CREATE UNIQUE INDEX "IncentiveTrigger_versionId_eventType_key" ON "IncentiveTrigger"("versionId", "eventType");

-- CreateIndex
CREATE INDEX "IncentiveRule_versionId_sortOrder_idx" ON "IncentiveRule"("versionId", "sortOrder");

-- CreateIndex
CREATE UNIQUE INDEX "IncentiveRewardDefinition_versionId_slot_key" ON "IncentiveRewardDefinition"("versionId", "slot");

-- CreateIndex
CREATE UNIQUE INDEX "IncentiveBudget_versionId_key" ON "IncentiveBudget"("versionId");

-- CreateIndex
CREATE UNIQUE INDEX "IncentiveEvent_eventId_key" ON "IncentiveEvent"("eventId");

-- CreateIndex
CREATE INDEX "IncentiveEvent_status_nextAttemptAt_idx" ON "IncentiveEvent"("status", "nextAttemptAt");

-- CreateIndex
CREATE INDEX "IncentiveEvent_type_entityId_idx" ON "IncentiveEvent"("type", "entityId");

-- CreateIndex
CREATE INDEX "IncentiveEvent_userId_idx" ON "IncentiveEvent"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "IncentiveReferralCode_code_key" ON "IncentiveReferralCode"("code");

-- CreateIndex
CREATE INDEX "IncentiveReferralCode_userId_idx" ON "IncentiveReferralCode"("userId");

-- CreateIndex
CREATE INDEX "IncentiveReferralCode_campaignId_idx" ON "IncentiveReferralCode"("campaignId");

-- CreateIndex
CREATE UNIQUE INDEX "IncentiveReferralCode_userId_audience_scopeKey_key" ON "IncentiveReferralCode"("userId", "audience", "scopeKey");

-- CreateIndex
CREATE INDEX "IncentiveReferral_referrerUserId_idx" ON "IncentiveReferral"("referrerUserId");

-- CreateIndex
CREATE INDEX "IncentiveReferral_codeId_idx" ON "IncentiveReferral"("codeId");

-- CreateIndex
CREATE INDEX "IncentiveReferral_status_idx" ON "IncentiveReferral"("status");

-- CreateIndex
CREATE INDEX "IncentiveReferral_campaignId_idx" ON "IncentiveReferral"("campaignId");

-- CreateIndex
CREATE UNIQUE INDEX "IncentiveReferral_referredUserId_acquisitionKind_key" ON "IncentiveReferral"("referredUserId", "acquisitionKind");

-- CreateIndex
CREATE UNIQUE INDEX "IncentiveReward_idempotencyKey_key" ON "IncentiveReward"("idempotencyKey");

-- CreateIndex
CREATE INDEX "IncentiveReward_recipientUserId_status_idx" ON "IncentiveReward"("recipientUserId", "status");

-- CreateIndex
CREATE INDEX "IncentiveReward_status_idx" ON "IncentiveReward"("status");

-- CreateIndex
CREATE INDEX "IncentiveReward_couponId_idx" ON "IncentiveReward"("couponId");

-- CreateIndex
CREATE INDEX "IncentiveReward_sourceEventId_idx" ON "IncentiveReward"("sourceEventId");

-- CreateIndex
CREATE UNIQUE INDEX "IncentiveReward_campaignVersionId_sourceEventId_recipientUs_key" ON "IncentiveReward"("campaignVersionId", "sourceEventId", "recipientUserId", "rewardSlot");

-- CreateIndex
CREATE UNIQUE INDEX "IncentiveLedgerEntry_idempotencyKey_key" ON "IncentiveLedgerEntry"("idempotencyKey");

-- CreateIndex
CREATE INDEX "IncentiveLedgerEntry_rewardId_createdAt_idx" ON "IncentiveLedgerEntry"("rewardId", "createdAt");

-- CreateIndex
CREATE INDEX "IncentiveRedemption_rewardId_idx" ON "IncentiveRedemption"("rewardId");

-- CreateIndex
CREATE INDEX "IncentiveRedemption_orderId_idx" ON "IncentiveRedemption"("orderId");

-- CreateIndex
CREATE INDEX "IncentiveRiskEvaluation_subjectType_subjectId_createdAt_idx" ON "IncentiveRiskEvaluation"("subjectType", "subjectId", "createdAt");

-- CreateIndex
CREATE INDEX "IncentiveApproval_rewardId_createdAt_idx" ON "IncentiveApproval"("rewardId", "createdAt");

-- CreateIndex
CREATE INDEX "IncentiveAuditLog_campaignId_createdAt_idx" ON "IncentiveAuditLog"("campaignId", "createdAt");

-- CreateIndex
CREATE INDEX "IncentiveAuditLog_actorId_createdAt_idx" ON "IncentiveAuditLog"("actorId", "createdAt");

-- AddForeignKey
ALTER TABLE "IncentiveCampaignVersion" ADD CONSTRAINT "IncentiveCampaignVersion_campaignId_fkey" FOREIGN KEY ("campaignId") REFERENCES "IncentiveCampaign"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IncentiveAudience" ADD CONSTRAINT "IncentiveAudience_versionId_fkey" FOREIGN KEY ("versionId") REFERENCES "IncentiveCampaignVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IncentiveTrigger" ADD CONSTRAINT "IncentiveTrigger_versionId_fkey" FOREIGN KEY ("versionId") REFERENCES "IncentiveCampaignVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IncentiveRule" ADD CONSTRAINT "IncentiveRule_versionId_fkey" FOREIGN KEY ("versionId") REFERENCES "IncentiveCampaignVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IncentiveRewardDefinition" ADD CONSTRAINT "IncentiveRewardDefinition_versionId_fkey" FOREIGN KEY ("versionId") REFERENCES "IncentiveCampaignVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IncentiveBudget" ADD CONSTRAINT "IncentiveBudget_versionId_fkey" FOREIGN KEY ("versionId") REFERENCES "IncentiveCampaignVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IncentiveReferralCode" ADD CONSTRAINT "IncentiveReferralCode_campaignId_fkey" FOREIGN KEY ("campaignId") REFERENCES "IncentiveCampaign"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IncentiveReferral" ADD CONSTRAINT "IncentiveReferral_codeId_fkey" FOREIGN KEY ("codeId") REFERENCES "IncentiveReferralCode"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IncentiveReferral" ADD CONSTRAINT "IncentiveReferral_campaignId_fkey" FOREIGN KEY ("campaignId") REFERENCES "IncentiveCampaign"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IncentiveReward" ADD CONSTRAINT "IncentiveReward_campaignVersionId_fkey" FOREIGN KEY ("campaignVersionId") REFERENCES "IncentiveCampaignVersion"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IncentiveReward" ADD CONSTRAINT "IncentiveReward_referralId_fkey" FOREIGN KEY ("referralId") REFERENCES "IncentiveReferral"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IncentiveLedgerEntry" ADD CONSTRAINT "IncentiveLedgerEntry_rewardId_fkey" FOREIGN KEY ("rewardId") REFERENCES "IncentiveReward"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IncentiveRedemption" ADD CONSTRAINT "IncentiveRedemption_rewardId_fkey" FOREIGN KEY ("rewardId") REFERENCES "IncentiveReward"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IncentiveApproval" ADD CONSTRAINT "IncentiveApproval_rewardId_fkey" FOREIGN KEY ("rewardId") REFERENCES "IncentiveReward"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
```

## 2. Event processing

```sql
-- AlterTable
ALTER TABLE "IncentiveEvent" ADD COLUMN "claimedAt" TIMESTAMP(3),
ADD COLUMN "claimedBy" TEXT,
ADD COLUMN "claimToken" TEXT;

-- AlterTable
ALTER TABLE "IncentiveAuditLog" ADD COLUMN "incentiveEventId" TEXT,
ADD COLUMN "attemptNumber" INTEGER;

-- CreateIndex
CREATE INDEX "IncentiveAuditLog_incentiveEventId_idx" ON "IncentiveAuditLog"("incentiveEventId");

-- AddForeignKey
ALTER TABLE "IncentiveAuditLog" ADD CONSTRAINT "IncentiveAuditLog_incentiveEventId_fkey" FOREIGN KEY ("incentiveEventId") REFERENCES "IncentiveEvent"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- One terminal incentive event per order, including concurrent inserts of different types.
CREATE UNIQUE INDEX "IncentiveEvent_one_terminal_order_event"
ON "IncentiveEvent" ("entityId")
WHERE "entityType" = 'order'
  AND "type" IN ('ORDER_QUALIFIED', 'ORDER_CANCELLED', 'ORDER_REJECTED');

-- One stored processing outcome per event, action, and attempt. Replay rows are not included.
CREATE UNIQUE INDEX "IncentiveAuditLog_processing_outcome_key"
ON "IncentiveAuditLog" ("incentiveEventId", "action", "attemptNumber")
WHERE "incentiveEventId" IS NOT NULL
  AND "action" IN ('EVENT_PROCESSED', 'EVENT_SKIPPED', 'EVENT_FAILED', 'EVENT_DEAD', 'EVENT_RECOVERED');
```

## 3. Referral code pin

```sql
-- Nullable so existing referral-code rows stay valid. No foreign key.

ALTER TABLE "IncentiveReferralCode" ADD COLUMN "expiresAt" TIMESTAMP(3),
ADD COLUMN "campaignVersionId" TEXT;
```

## 4. Referral attribution

```sql
-- No foreign keys to User, Order, or Listing. The user check is enforced in the database.

ALTER TABLE "IncentiveReferral" ADD COLUMN "campaignVersionId" TEXT,
ADD COLUMN "sellerEnabledAt" TIMESTAMP(3),
ADD COLUMN "listingId" TEXT,
ADD COLUMN "listingPublishedAt" TIMESTAMP(3),
ADD COLUMN "qualifyingOrderId" TEXT,
ADD COLUMN "qualifyingOrderAt" TIMESTAMP(3),
ADD COLUMN "qualifiedAt" TIMESTAMP(3),
ADD COLUMN "disqualifyReason" TEXT;

ALTER TABLE "IncentiveReferral" ADD CONSTRAINT "IncentiveReferral_users_distinct"
CHECK ("referrerUserId" <> "referredUserId");

CREATE INDEX "IncentiveReferral_referrer_version_kind_idx"
ON "IncentiveReferral" ("referrerUserId", "campaignVersionId", "acquisitionKind");
```

## 5. Listing first published at

```sql
-- Null for drafts and for listings published before this column existed.

ALTER TABLE "Listing" ADD COLUMN "firstPublishedAt" TIMESTAMP(3);
```

## 6. Ledger guard

```sql
-- Replaces the ledger guard with a reward-row lock before the balance sum.
-- Does not alter Coupon, Order, User, Listing, or AppSetting.
-- Rollback, after an approved apply:
-- DROP TRIGGER IF EXISTS incentive_ledger_no_update ON "IncentiveLedgerEntry";
-- DROP TRIGGER IF EXISTS incentive_ledger_no_delete ON "IncentiveLedgerEntry";
-- DROP TRIGGER IF EXISTS incentive_ledger_guard_insert ON "IncentiveLedgerEntry";
-- DROP FUNCTION IF EXISTS incentive_ledger_reject_mutation();
-- DROP FUNCTION IF EXISTS incentive_ledger_guard_insert();

CREATE OR REPLACE FUNCTION incentive_ledger_reject_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'IncentiveLedgerEntry is append-only';
END;
$$;

DROP TRIGGER IF EXISTS incentive_ledger_no_update ON "IncentiveLedgerEntry";
CREATE TRIGGER incentive_ledger_no_update
BEFORE UPDATE ON "IncentiveLedgerEntry"
FOR EACH ROW
EXECUTE FUNCTION incentive_ledger_reject_mutation();

DROP TRIGGER IF EXISTS incentive_ledger_no_delete ON "IncentiveLedgerEntry";
CREATE TRIGGER incentive_ledger_no_delete
BEFORE DELETE ON "IncentiveLedgerEntry"
FOR EACH ROW
EXECUTE FUNCTION incentive_ledger_reject_mutation();

-- VOLATILE is required. In READ COMMITTED, each statement inside a volatile
-- PL/pgSQL function takes its snapshot when that statement starts. The
-- SELECT FOR UPDATE waits until the other transaction commits and releases
-- the reward row. The SUM starts only after that wait, so its snapshot
-- includes the ledger rows that transaction committed. Debits for one reward
-- are serialized. Debits for different rewards lock different rows.
CREATE OR REPLACE FUNCTION incentive_ledger_guard_insert()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  locked_reward text;
  current_balance numeric(12,2);
BEGIN
  IF NEW."rewardId" IS NULL OR NEW."entryType" IS NULL OR NEW."idempotencyKey" IS NULL OR btrim(NEW."idempotencyKey") = '' THEN
    RAISE EXCEPTION 'IncentiveLedgerEntry requires a source and an idempotency key';
  END IF;

  IF NEW."entryType" = 'ISSUE' THEN
    IF NEW."amount" <= 0 THEN
      RAISE EXCEPTION 'IncentiveLedgerEntry ISSUE amount must be positive';
    END IF;
  ELSIF NEW."entryType" = 'REDEEM' THEN
    IF NEW."amount" >= 0 THEN
      RAISE EXCEPTION 'IncentiveLedgerEntry REDEEM amount must be negative';
    END IF;
  ELSIF NEW."entryType" = 'EXPIRE' THEN
    IF NEW."amount" >= 0 THEN
      RAISE EXCEPTION 'IncentiveLedgerEntry EXPIRE amount must be negative';
    END IF;
  ELSE
    RAISE EXCEPTION 'IncentiveLedgerEntry entry type is not supported';
  END IF;

  SELECT "id" INTO locked_reward
  FROM "IncentiveReward"
  WHERE "id" = NEW."rewardId"
  FOR UPDATE;

  IF locked_reward IS NULL THEN
    RAISE EXCEPTION 'IncentiveLedgerEntry reward is missing';
  END IF;

  SELECT COALESCE(SUM("amount"), 0) INTO current_balance
  FROM "IncentiveLedgerEntry"
  WHERE "rewardId" = NEW."rewardId";

  IF current_balance + NEW."amount" < 0 THEN
    RAISE EXCEPTION 'IncentiveLedgerEntry would make the balance negative';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS incentive_ledger_guard_insert ON "IncentiveLedgerEntry";
CREATE TRIGGER incentive_ledger_guard_insert
BEFORE INSERT ON "IncentiveLedgerEntry"
FOR EACH ROW
EXECUTE FUNCTION incentive_ledger_guard_insert();
```
