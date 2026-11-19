const { httpError } = require("../lib/httpError");
const { evaluateRules } = require("../rules/evaluate");
const { flattenRules } = require("../rules/validate");
const {
  assertBudgetCoversRewards,
  assertWindow,
  parseAudiences,
  parseBudget,
  parseEligibility,
  parseHeader,
  parseReferralPolicy,
  parseRewards,
  parseTriggers,
} = require("./config");
const { assessCampaign } = require("./readiness");
const {
  TERMINAL,
  activationTarget,
  assertCanActivate,
  assertCategoryFlags,
  assertTransition,
} = require("./lifecycle");

function snapshotFrom(campaign, parts) {
  return {
    schemaVersion: 1,
    name: campaign.name,
    description: campaign.description || null,
    category: campaign.category,
    priority: campaign.priority,
    stackingMode: campaign.stackingMode,
    startsAt: campaign.startsAt || null,
    endsAt: campaign.endsAt || null,
    audiences: parts.audiences || [],
    triggers: parts.triggers || [],
    eligibility: parts.eligibility || null,
    rules: parts.rules || null,
    rewards: parts.rewards || [],
    budget: parts.budget || null,
    referralPolicy: parts.referralPolicy || null,
  };
}

function versionRecord(campaignId, versionNumber, snapshot) {
  return {
    campaignId,
    versionNumber,
    snapshot,
    publishedAt: null,
    publishedBy: null,
    audiences: snapshot.audiences,
    triggers: snapshot.triggers.map((trigger) => ({ eventType: trigger.eventType })),
    rules: flattenRules(snapshot.rules),
    rewards: snapshot.rewards,
    budget: snapshot.budget,
  };
}

function present(campaign, version) {
  return {
    id: campaign.id,
    name: campaign.name,
    description: campaign.description || null,
    category: campaign.category,
    status: campaign.status,
    priority: campaign.priority,
    stackingMode: campaign.stackingMode,
    startsAt: campaign.startsAt || null,
    endsAt: campaign.endsAt || null,
    currentVersionId: campaign.currentVersionId || null,
    createdBy: campaign.createdBy || null,
    createdAt: campaign.createdAt,
    updatedAt: campaign.updatedAt,
    version: version
      ? {
          id: version.id,
          versionNumber: version.versionNumber,
          publishedAt: version.publishedAt || null,
          publishedBy: version.publishedBy || null,
          processor: "NOT_IMPLEMENTED",
          snapshot: version.snapshot,
        }
      : null,
  };
}

async function mustCampaign(repository, campaignId) {
  const campaign = await repository.getCampaign(campaignId);
  if (!campaign) throw httpError(404, "Campaign not found");
  return campaign;
}

async function mustVersion(repository, versionId) {
  const version = await repository.getVersion(versionId);
  if (!version) throw httpError(404, "Campaign version not found");
  return version;
}

async function editableVersion(repository, campaign, actorId) {
  if (TERMINAL.has(campaign.status)) {
    throw httpError(409, "A finished campaign cannot be edited");
  }
  const current = await mustVersion(repository, campaign.currentVersionId);
  if (campaign.status === "DRAFT" && !current.publishedAt) {
    return { campaign, version: current };
  }
  const versions = await repository.listVersions(campaign.id);
  const versionNumber = versions.reduce((max, row) => Math.max(max, row.versionNumber), 0) + 1;
  const created = await repository.createVersion(
    versionRecord(campaign.id, versionNumber, current.snapshot)
  );
  const saved = await repository.saveCampaign({
    ...campaign,
    status: "DRAFT",
    currentVersionId: created.id,
  });
  await repository.appendAudit({
    actorId: actorId || campaign.createdBy || null,
    action: "CAMPAIGN_VERSION_FORKED",
    campaignId: campaign.id,
    before: { versionId: current.id, status: campaign.status },
    after: { versionId: created.id, status: "DRAFT" },
  });
  return { campaign: saved, version: created };
}

async function saveEditable(repository, campaign, version, snapshot, actorId, action) {
  assertBudgetCoversRewards(snapshot.budget, snapshot.rewards);
  const savedVersion = await repository.saveVersion({
    ...versionRecord(campaign.id, version.versionNumber, snapshot),
    id: version.id,
    publishedAt: null,
    publishedBy: null,
    createdAt: version.createdAt,
  });
  const savedCampaign = await repository.saveCampaign({
    ...campaign,
    name: snapshot.name,
    description: snapshot.description,
    category: snapshot.category,
    priority: snapshot.priority,
    stackingMode: snapshot.stackingMode,
    startsAt: snapshot.startsAt,
    endsAt: snapshot.endsAt,
    status: "DRAFT",
    currentVersionId: version.id,
  });
  await repository.appendAudit({
    actorId,
    action,
    campaignId: campaign.id,
    before: { versionId: version.id },
    after: { versionId: savedVersion.id, status: "DRAFT" },
  });
  return present(savedCampaign, savedVersion);
}

async function createCampaign(repository, { actorId, body }) {
  const header = parseHeader(body);
  assertWindow(header.startsAt || null, header.endsAt || null);
  const campaign = await repository.createCampaign({
    name: header.name,
    description: header.description || null,
    category: header.category,
    priority: header.priority == null ? 0 : header.priority,
    stackingMode: header.stackingMode || "STACK",
    startsAt: header.startsAt || null,
    endsAt: header.endsAt || null,
    createdBy: actorId,
  });
  const snapshot = snapshotFrom(campaign, {});
  const version = await repository.createVersion(versionRecord(campaign.id, 1, snapshot));
  const saved = await repository.saveCampaign({ ...campaign, currentVersionId: version.id });
  await repository.appendAudit({
    actorId,
    action: "CAMPAIGN_CREATED",
    campaignId: saved.id,
    before: null,
    after: { status: "DRAFT", versionId: version.id },
  });
  return present(saved, version);
}

async function listCampaigns(repository) {
  const rows = await repository.listCampaigns();
  return rows.map((row) => present(row, null));
}

async function getCampaign(repository, campaignId) {
  const campaign = await mustCampaign(repository, campaignId);
  const version = campaign.currentVersionId ? await mustVersion(repository, campaign.currentVersionId) : null;
  return present(campaign, version);
}

async function updateCampaign(repository, { campaignId, actorId, body }) {
  const campaign = await mustCampaign(repository, campaignId);
  const header = parseHeader(body, { partial: true });
  const editable = await editableVersion(repository, campaign, actorId);
  const merged = { ...editable.campaign, ...header, status: "DRAFT", currentVersionId: editable.version.id };
  assertWindow(merged.startsAt || null, merged.endsAt || null);
  const snapshot = snapshotFrom(merged, editable.version.snapshot);
  return saveEditable(repository, merged, editable.version, snapshot, actorId, "CAMPAIGN_UPDATED");
}

async function replaceSection(repository, { campaignId, actorId, apply, action }) {
  const campaign = await mustCampaign(repository, campaignId);
  const editable = await editableVersion(repository, campaign, actorId);
  const parts = {
    audiences: editable.version.snapshot.audiences,
    triggers: editable.version.snapshot.triggers,
    eligibility: editable.version.snapshot.eligibility || null,
    rules: editable.version.snapshot.rules,
    rewards: editable.version.snapshot.rewards,
    budget: editable.version.snapshot.budget,
    referralPolicy: editable.version.snapshot.referralPolicy || null,
  };
  apply(parts);
  assertWindow(editable.campaign.startsAt || null, editable.campaign.endsAt || null);
  const snapshot = snapshotFrom(editable.campaign, parts);
  return saveEditable(repository, editable.campaign, editable.version, snapshot, actorId, action);
}

function setAudiences(repository, args) {
  const audiences = parseAudiences(args.body && args.body.audiences);
  return replaceSection(repository, {
    ...args,
    action: "CAMPAIGN_AUDIENCE_SET",
    apply(parts) {
      parts.audiences = audiences;
    },
  });
}

function setTriggers(repository, args) {
  const triggers = parseTriggers(args.body && args.body.triggers);
  return replaceSection(repository, {
    ...args,
    action: "CAMPAIGN_TRIGGERS_SET",
    apply(parts) {
      parts.triggers = triggers;
    },
  });
}

function setRules(repository, args) {
  const parsed = parseEligibility(args.body || {});
  return replaceSection(repository, {
    ...args,
    action: "CAMPAIGN_RULES_SET",
    apply(parts) {
      parts.eligibility = parsed.eligibility;
      parts.rules = parsed.rules;
    },
  });
}

function setRewards(repository, args) {
  const rewards = parseRewards(args.body && args.body.rewards);
  return replaceSection(repository, {
    ...args,
    action: "CAMPAIGN_REWARDS_SET",
    apply(parts) {
      assertBudgetCoversRewards(parts.budget, rewards);
      parts.rewards = rewards;
    },
  });
}

function setReferralPolicy(repository, args) {
  return (async () => {
    const campaign = await mustCampaign(repository, args.campaignId);
    const referralPolicy = parseReferralPolicy(args.body && args.body.referralPolicy, {
      category: campaign.category,
      endsAt: campaign.endsAt,
    });
    return replaceSection(repository, {
      ...args,
      action: "CAMPAIGN_REFERRAL_POLICY_SET",
      apply(parts) {
        parts.referralPolicy = referralPolicy;
      },
    });
  })();
}

function setBudget(repository, args) {
  const budget = parseBudget(args.body || {});
  return replaceSection(repository, {
    ...args,
    action: "CAMPAIGN_BUDGET_SET",
    apply(parts) {
      assertBudgetCoversRewards(budget, parts.rewards);
      parts.budget = budget;
    },
  });
}

async function listVersions(repository, campaignId) {
  await mustCampaign(repository, campaignId);
  const versions = await repository.listVersions(campaignId);
  return versions.map((version) => ({
    id: version.id,
    versionNumber: version.versionNumber,
    publishedAt: version.publishedAt || null,
    publishedBy: version.publishedBy || null,
    processor: "NOT_IMPLEMENTED",
  }));
}

async function getVersion(repository, campaignId, versionId) {
  await mustCampaign(repository, campaignId);
  const version = await mustVersion(repository, versionId);
  if (version.campaignId !== campaignId) throw httpError(404, "Campaign version not found");
  return {
    id: version.id,
    versionNumber: version.versionNumber,
    publishedAt: version.publishedAt || null,
    publishedBy: version.publishedBy || null,
    processor: "NOT_IMPLEMENTED",
    snapshot: version.snapshot,
  };
}

function audienceHit(audience, attributes) {
  if (audience.kind === "ALL_USERS") return true;
  const role = attributes["user.role"];
  if (audience.kind === "BUYERS") return role === "buyer";
  if (audience.kind === "SELLERS") return role === "seller";
  if (audience.kind === "NEW_USERS") return attributes["user.isNew"] === true;
  if (audience.kind === "EXISTING_USERS") return attributes["user.isNew"] === false;
  if (audience.kind === "FIRST_TIME_BUYERS") return attributes["order.isFirstCompleted"] === true;
  if (audience.kind === "ACTIVE_BUYERS") return attributes["user.activeBuyer"] === true;
  if (audience.kind === "INACTIVE_BUYERS") return attributes["user.inactiveBuyer"] === true;
  if (audience.kind === "NEW_SELLERS") return attributes["user.newSeller"] === true;
  if (audience.kind === "SOCIETIES") return (audience.payload.societyIds || []).includes(attributes["user.societyId"]);
  if (audience.kind === "CITIES") return (audience.payload.cityKeys || []).includes(attributes["user.cityKey"]);
  if (audience.kind === "REGIONS") return (audience.payload.regions || []).includes(attributes["user.region"]);
  if (audience.kind === "CUSTOM_SEGMENT") return attributes["user.segmentKey"] === audience.payload.segmentKey;
  return false;
}

function explainAudience(audiences, attributes, explicitAllUsers) {
  if (!audiences.length) {
    return {
      configured: false,
      matchesEveryone: false,
      passed: false,
      checks: [],
      reason: "Audience is not configured",
    };
  }
  if (audiences.some((row) => row.kind === "ALL_USERS") && audiences.length > 1) {
    return {
      configured: false,
      matchesEveryone: false,
      passed: false,
      checks: [],
      reason: "ALL_USERS cannot be combined with another audience",
    };
  }
  const checks = audiences.map((audience) => ({
    kind: audience.kind,
    passed: audienceHit(audience, attributes),
  }));
  return {
    configured: true,
    matchesEveryone: explicitAllUsers,
    passed: checks.some((check) => check.passed),
    checks,
    reason: explicitAllUsers ? "Explicit all-user audience" : null,
  };
}

function explainTrigger(triggers, attributes) {
  if (!triggers.length) {
    return {
      passed: false,
      configured: [],
      processor: "NOT_IMPLEMENTED",
      reason: "No trigger configured",
    };
  }
  return {
    passed: triggers.some((row) => row.eventType === attributes["event.type"]),
    eventType: attributes["event.type"] || null,
    configured: triggers.map((row) => row.eventType),
    processor: "NOT_IMPLEMENTED",
  };
}

function explainRules(snapshot) {
  if (snapshot.eligibility === "AUDIENCE_AND_TRIGGER_ONLY") {
    return {
      passed: true,
      results: [],
      reason: "Eligibility policy uses the audience and trigger only",
    };
  }
  if (snapshot.eligibility === "RULES") {
    if (snapshot.rules) return null;
    return { passed: false, results: [], reason: "Rules policy requires a non-empty rule tree" };
  }
  return { passed: false, results: [], reason: "Eligibility policy is not configured" };
}

function explainSimulation(snapshot, attributes) {
  const source = attributes && typeof attributes === "object" ? attributes : {};
  const stored = snapshot && typeof snapshot === "object" ? snapshot : {};
  const assessment = assessCampaign(stored);
  const audiences = stored.audiences || [];
  const audience = explainAudience(audiences, source, assessment.explicitAllUsers);
  const trigger = explainTrigger(stored.triggers || [], source);
  const presetRules = explainRules(stored);
  const rules = presetRules || evaluateRules(stored.rules, source);
  const sampleMatches = audience.passed && trigger.passed && rules.passed;
  const passed = assessment.ready && sampleMatches;
  return {
    ready: assessment.ready,
    passed,
    eligible: passed,
    matchesEveryone: assessment.matchesEveryone,
    reason: assessment.ready ? null : assessment.failures[0].message,
    failures: assessment.failures,
    audience,
    eligibility: {
      policy: assessment.policy,
      passed: assessment.policy === "RULES" ? rules.passed : assessment.policy === "AUDIENCE_AND_TRIGGER_ONLY",
      reason: rules.reason || null,
    },
    trigger,
    rules,
    rewards: (stored.rewards || []).map((reward) => ({ ...reward, issued: false })),
    budget: stored.budget ? { ...stored.budget, consumed: false } : null,
    writes: 0,
  };
}

async function simulate(repository, { campaignId, versionId, attributes }) {
  const writesBefore = typeof repository.writes === "function" ? repository.writes() : null;
  const campaign = await mustCampaign(repository, campaignId);
  const version = await mustVersion(repository, versionId || campaign.currentVersionId);
  if (version.campaignId !== campaign.id) throw httpError(404, "Campaign version not found");
  const explanation = explainSimulation(version.snapshot, attributes);
  if (writesBefore != null && repository.writes() !== writesBefore) {
    throw httpError(500, "Simulation must not write campaign data");
  }
  return {
    campaignId: campaign.id,
    versionId: version.id,
    versionNumber: version.versionNumber,
    ...explanation,
  };
}

async function changeStatus(repository, { campaignId, actorId, to, now = new Date(), flags }) {
  const campaign = await mustCampaign(repository, campaignId);
  let target = to;
  if (to === "ACTIVATE") {
    assertCanActivate(flags);
    assertCategoryFlags(campaign, flags);
    const version = await mustVersion(repository, campaign.currentVersionId);
    const assessment = assessCampaign(version.snapshot);
    if (!assessment.ready) {
      const failure = assessment.failures[0];
      throw httpError(400, failure.message, failure.code);
    }
    target = activationTarget(campaign, now);
    assertTransition(campaign.status, target);
    let published = version;
    if (!version.publishedAt) {
      published = await repository.saveVersion({
        ...version,
        publishedAt: now.toISOString(),
        publishedBy: actorId,
      });
    }
    const saved = await repository.saveCampaign({ ...campaign, status: target });
    await repository.appendAudit({
      actorId,
      action: "CAMPAIGN_ACTIVATED",
      campaignId: campaign.id,
      before: { status: campaign.status },
      after: { status: target, versionId: published.id },
    });
    return present(saved, published);
  }
  if (to === "EXPIRED") {
    if (!campaign.endsAt || new Date(campaign.endsAt) > now) {
      throw httpError(400, "Campaign window has not ended");
    }
  }
  assertTransition(campaign.status, target);
  const saved = await repository.saveCampaign({ ...campaign, status: target });
  const version = await mustVersion(repository, saved.currentVersionId);
  await repository.appendAudit({
    actorId,
    action: `CAMPAIGN_${target}`,
    campaignId: campaign.id,
    before: { status: campaign.status },
    after: { status: target },
  });
  return present(saved, version);
}

async function duplicateCampaign(repository, { campaignId, actorId, body }) {
  const source = await getCampaign(repository, campaignId);
  const requested = body && typeof body.name === "string" ? body.name.trim() : "";
  if (!requested) throw httpError(400, "A new campaign name is required", "NAME_REQUIRED");
  if (requested.toLowerCase() === String(source.name || "").trim().toLowerCase()) {
    throw httpError(400, "The copy needs a different campaign name", "NAME_UNCHANGED");
  }
  const created = await createCampaign(repository, {
    actorId,
    body: {
      name: requested,
      description: source.description,
      category: source.category,
      priority: source.priority,
      stackingMode: source.stackingMode,
      startsAt: source.startsAt,
      endsAt: source.endsAt,
    },
  });
  const snapshot = (source.version && source.version.snapshot) || {};
  const copyId = created.id;
  if (Array.isArray(snapshot.audiences) && snapshot.audiences.length) {
    await setAudiences(repository, { campaignId: copyId, actorId, body: { audiences: snapshot.audiences } });
  }
  if (Array.isArray(snapshot.triggers) && snapshot.triggers.length) {
    await setTriggers(repository, { campaignId: copyId, actorId, body: { triggers: snapshot.triggers } });
  }
  if (snapshot.eligibility) {
    await setRules(repository, {
      campaignId: copyId,
      actorId,
      body: {
        eligibility: snapshot.eligibility,
        ...(snapshot.eligibility === "RULES" ? { rules: snapshot.rules } : {}),
      },
    });
  }
  if (snapshot.budget) {
    await setBudget(repository, {
      campaignId: copyId,
      actorId,
      body: {
        amountCap: snapshot.budget.amountCap,
        currency: snapshot.budget.currency || "INR",
        maxRewardCount: snapshot.budget.maxRewardCount,
        maxRewardAmount: snapshot.budget.maxRewardAmount,
      },
    });
  }
  if (Array.isArray(snapshot.rewards) && snapshot.rewards.length) {
    await setRewards(repository, { campaignId: copyId, actorId, body: { rewards: snapshot.rewards } });
  }
  if (snapshot.referralPolicy) {
    await setReferralPolicy(repository, {
      campaignId: copyId,
      actorId,
      body: { referralPolicy: snapshot.referralPolicy },
    });
  }
  await repository.appendAudit({
    actorId,
    action: "CAMPAIGN_DUPLICATED",
    campaignId: copyId,
    before: { sourceCampaignId: source.id },
    after: { status: "DRAFT", sourceCampaignId: source.id },
  });
  const unchanged = await getCampaign(repository, source.id);
  if (unchanged.status !== source.status || unchanged.currentVersionId !== source.currentVersionId) {
    throw httpError(500, "Duplicating a campaign changed the source campaign");
  }
  return getCampaign(repository, copyId);
}

module.exports = {
  assessCampaign,
  changeStatus,
  createCampaign,
  duplicateCampaign,
  explainSimulation,
  getCampaign,
  getVersion,
  listCampaigns,
  listVersions,
  setAudiences,
  setBudget,
  setReferralPolicy,
  setRewards,
  setRules,
  setTriggers,
  simulate,
  updateCampaign,
};
