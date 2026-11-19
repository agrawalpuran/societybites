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

