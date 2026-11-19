process.env.DATABASE_URL = "postgresql://postgres@127.0.0.1:5432/societybites_incentive_unit";
process.env.DIRECT_URL = process.env.DATABASE_URL;

const fs = require("fs");
const path = require("path");
const http = require("http");
const express = require("express");
const { flagsOff } = require("../modules/incentive-engine/configuration/flags");
const { createAssignedCoupon } = require("../lib/coupons");
const { issueMatchedRewards } = require("../modules/incentive-engine/rewards/issue");
const { balanceOf, postEntry } = require("../modules/incentive-engine/rewards/ledger");
const { approveReward, expireDueRewards, redeemReward, rejectReward } = require("../modules/incentive-engine/rewards/approve");
const { createRewardsRouter } = require("../modules/incentive-engine/routes/adminRewards");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function store() {
  const state = {
    rewards: [],
    entries: [],
    redemptions: [],
    approvals: [],
    audits: [],
    coupons: [],
    users: [],
    budgets: [],
    versions: [],
    referrals: [],
  };
  function rewardApi(snapshot) {
    return {
      rows: snapshot.rewards,
      lockState: { queues: new Map(), held: new Set() },
      async create({ data }) {
        if (snapshot.rewards.some((row) => row.idempotencyKey === data.idempotencyKey)) {
          const error = new Error("Unique constraint failed");
          error.code = "P2002";
          throw error;
        }
        const row = { id: `reward-${snapshot.rewards.length + 1}`, ...data };
        snapshot.rewards.push(row);
        return { ...row };
      },
      async findUnique({ where }) {
        return snapshot.rewards.find((row) => row.id === where.id || row.idempotencyKey === where.idempotencyKey) || null;
      },
      async findMany() {
        return snapshot.rewards.map((row) => ({ ...row }));
      },
      async count({ where }) {
        return snapshot.rewards.filter((row) => row.campaignVersionId === where.campaignVersionId && row.status !== "REJECTED").length;
      },
      async update({ where, data }) {
        const row = snapshot.rewards.find((item) => item.id === where.id);
        Object.assign(row, data);
        return { ...row };
      },
    };
  }
  function entryApi(snapshot) {
    return {
      async create({ data }) {
        if (snapshot.entries.some((row) => row.idempotencyKey === data.idempotencyKey)) {
          const error = new Error("Unique constraint failed");
          error.code = "P2002";
          throw error;
        }
        const row = { id: `entry-${snapshot.entries.length + 1}`, ...data };
        snapshot.entries.push(row);
        return { ...row };
      },
      async findUnique({ where }) {
        return snapshot.entries.find((row) => row.idempotencyKey === where.idempotencyKey) || null;
      },
      async findMany({ where }) {
        return snapshot.entries.filter((row) => row.rewardId === where.rewardId);
      },
    };
  }
  function budgetApi(snapshot) {
    return {
      rows: snapshot.budgets,
      queues: new Map(),
      held: new Set(),
      async findUnique({ where }) {
        return snapshot.budgets.find((row) => row.versionId === where.versionId || row.id === where.id) || null;
      },
      async update({ where, data }) {
        const row = snapshot.budgets.find((item) => item.id === where.id);
        Object.assign(row, data);
        return { ...row };
      },
    };
  }
  function clientFor(snapshot) {
    return {
      incentiveReward: rewardApi(snapshot),
      incentiveLedgerEntry: entryApi(snapshot),
      incentiveBudget: budgetApi(snapshot),
      incentiveReferral: {
        async findFirst({ where }) {
          return snapshot.referrals.find((row) => row.id === where.id || row.referredUserId === where.referredUserId) || null;
        },
      },
      incentiveCampaignVersion: {
        async findUnique({ where }) {
          return snapshot.versions.find((row) => row.id === where.id) || null;
        },
      },
      incentiveRedemption: {
        async create({ data }) {
          const row = { id: `redemption-${snapshot.redemptions.length + 1}`, ...data };
          snapshot.redemptions.push(row);
          return row;
        },
        async findFirst({ where }) {
          return snapshot.redemptions.find((row) => row.rewardId === where.rewardId) || null;
        },
        async findMany({ where }) {
          return snapshot.redemptions.filter((row) => row.rewardId === where.rewardId);
        },
      },
      incentiveApproval: {
        async create({ data }) {
          snapshot.approvals.push(data);
          return data;
        },
      },
      incentiveAuditLog: {
        async create({ data }) {
          snapshot.audits.push(data);
          return data;
        },
      },
      incentiveSetting: {
        async lock() {
          if (snapshot.settingError) throw new Error(snapshot.settingError);
          return snapshot.issuanceValue == null ? null : snapshot.issuanceValue;
        },
      },
      async $transaction(work) {
        const copy = clone(snapshot);
        const tx = clientFor(copy);
        tx.incentiveBudget.queues = this.incentiveBudget.queues;
        tx.incentiveBudget.held = this.incentiveBudget.held;
        tx.incentiveReward.lockState = this.incentiveReward.lockState;
        try {
          const result = await work(tx);
          snapshot.rewards = copy.rewards;
          snapshot.entries = copy.entries;
          snapshot.redemptions = copy.redemptions;
          snapshot.approvals = copy.approvals;
          snapshot.audits = copy.audits;
          snapshot.budgets = copy.budgets;
          snapshot.coupons = copy.coupons;
          snapshot.users = copy.users;
          return result;
        } catch (error) {
          throw error;
        }
      },
    };
  }
  const root = clientFor(state);
  root.state = state;
  root.couponWriter = async (tx, spec) => {
    if (state.failCoupon) throw new Error("coupon database unavailable");
    const coupon = { id: `coupon-${state.coupons.length + 1}`, ...spec };
    state.coupons.push(coupon);
    return coupon;
  };
  return root;
}

function campaign(overrides = {}) {
  return {
    id: "campaign-1",
    stackingMode: "STACK",
    priority: 10,
    version: {
      id: "version-1",
      snapshot: {
        budget: { amountCap: "100.00", maxRewardCount: null },
        rewards: [overrides.reward || {
          slot: "buyer",
          recipientRole: "BUYER",
          rewardType: "FIXED_COUPON",
          amount: "20.00",
          maxDiscount: null,
          minOrder: "0.00",
          expiryDays: 30,
          usageLimit: 1,
        }],
      },
    },
  };
}

function input(db, definition, flags = { issuance: true }) {
  const row = campaign({ reward: definition });
  db.state.budgets.push({ id: "budget-1", versionId: "version-1", amountCap: "100.00", issuedAmount: "0.00" });
  db.state.versions.push(row.version);
  return {
    event: { id: "event-1", type: "ORDER_QUALIFIED", userId: "buyer-1", entityId: "order-1" },
    matches: [{ campaignId: "campaign-1", passed: true }],
    campaigns: [row],
    flags,
    now: new Date("2026-11-17T12:00:00.000Z"),
    order: { buyerId: "buyer-1", items: [{ listing: { sellerId: "seller-1" } }] },
    couponWriter: db.couponWriter,
  };
}

async function testFixedAndPercentage() {
  const fixedDb = store();
  const fixed = await issueMatchedRewards(fixedDb, input(fixedDb, {
    slot: "buyer",
    recipientRole: "BUYER",
    rewardType: "FIXED_COUPON",
    amount: "20.00",
    expiryDays: 30,
    usageLimit: 1,
  }));
  assert(fixed.issued.length === 1, "fixed coupon reward is issued");
  assert(fixedDb.state.coupons[0].discountType === "FIXED", "fixed coupon uses the coupon discount type");
  assert(fixedDb.state.coupons[0].discountValue === 20, "fixed coupon value comes from the reward");
  assert(fixedDb.state.coupons[0].audienceType === "SELECTED_USERS", "coupon is limited to the recipient");
  assert(fixedDb.state.coupons[0].userIds[0] === "buyer-1", "coupon names the recipient");
  assert(fixedDb.state.entries.length === 0, "coupon rewards do not write promotional credit");

  const percentDb = store();
  const percent = await issueMatchedRewards(percentDb, input(percentDb, {
    slot: "buyer",
    recipientRole: "BUYER",
    rewardType: "PERCENTAGE_COUPON",
    amount: "10.00",
    maxDiscount: "50.00",
    minOrder: "100.00",
    expiryDays: 15,
  }));
  assert(percent.issued.length === 1, "percentage coupon reward is issued");
  assert(percentDb.state.coupons[0].discountType === "PERCENTAGE", "percentage coupon type");
  assert(percentDb.state.coupons[0].discountValue === 10, "percentage value");
  assert(percentDb.state.coupons[0].maximumDiscount === 50, "percentage cap");
  assert(percentDb.state.budgets[0].issuedAmount === "50.00", "percentage reserves its maximum discount");
}

async function testCreditDuplicateAndBudget() {
  const db = store();
  const spec = input(db, {
    slot: "credit",
    recipientRole: "TRIGGER_USER",
    rewardType: "PROMOTIONAL_CREDIT",
    amount: "15.00",
    expiryDays: 10,
  });
  const first = await issueMatchedRewards(db, spec);
  const second = await issueMatchedRewards(db, spec);
  assert(first.issued.length === 1 && second.issued.length === 1, "a repeated event returns the existing reward");
  assert(db.state.rewards.length === 1 && db.state.entries.length === 1, "duplicate processing does not create a second credit");
  assert(db.state.entries[0].idempotencyKey === "ISSUE:version-1:event-1:buyer-1:credit", "credit ledger key is deterministic");
  assert(await balanceOf(db, first.issued[0].id) === 15, "credit balance is the posted issue");

  const other = store();
  other.state.budgets.push({ id: "budget-1", versionId: "version-1", amountCap: "15.00", issuedAmount: "0.00" });
  const base = input(other, {
    slot: "credit",
    recipientRole: "TRIGGER_USER",
    rewardType: "PROMOTIONAL_CREDIT",
    amount: "15.00",
  });
  other.state.budgets.splice(1);
  const raced = await Promise.all([
    issueMatchedRewards(other, base),
    issueMatchedRewards(other, {
      ...base,
      event: { ...base.event, id: "event-2" },
    }),
  ]);
  const issued = raced.flatMap((row) => row.issued);
  const skipped = raced.flatMap((row) => row.skipped);
  assert(issued.length === 1, "concurrent issuance keeps one credit inside the budget");
  assert(skipped.some((row) => row.reason === "BUDGET_EXHAUSTED"), "the second concurrent credit is refused");
  assert(other.state.entries.length === 1, "budget exhaustion does not post a second credit");
}

async function testApprovalFailureAndFlags() {
  const db = store();
  const pending = await issueMatchedRewards(db, input(db, {
    slot: "buyer",
    recipientRole: "BUYER",
    rewardType: "FIXED_COUPON",
    amount: "20.00",
    requireAdminApproval: true,
  }));
  assert(pending.pending.length === 1 && pending.pending[0].status === "PENDING_APPROVAL", "approval policy holds the reward");
  assert(db.state.coupons.length === 0, "a pending reward has no coupon yet");
  db.state.issuanceValue = " true ";
  const approved = await approveReward(db, { rewardId: pending.pending[0].id, actorId: "admin-1", couponWriter: db.couponWriter });
  const again = await approveReward(db, { rewardId: pending.pending[0].id, actorId: "admin-1", couponWriter: db.couponWriter });
  assert(approved.status === "ISSUED" && again.id === approved.id, "approval is idempotent");
  assert(db.state.coupons.length === 1, "approval creates one coupon");

  const rejectDb = store();
  const rejectSpec = input(rejectDb, {
    slot: "credit",
    recipientRole: "TRIGGER_USER",
    rewardType: "PROMOTIONAL_CREDIT",
    amount: "15.00",
    requireAdminApproval: true,
  });
  const held = await issueMatchedRewards(rejectDb, rejectSpec);
  const rejected = await rejectReward(rejectDb, { rewardId: held.pending[0].id, actorId: "admin-1", reason: "No" });
  const rejectedAgain = await rejectReward(rejectDb, { rewardId: held.pending[0].id, actorId: "admin-1" });
  assert(rejected.status === "REJECTED" && rejectedAgain.status === "REJECTED", "rejection is idempotent");
  assert(rejectDb.state.entries.length === 0, "a rejected credit is not posted");
  assert(rejectDb.state.budgets[0].issuedAmount === "0.00", "rejection returns the reserved budget once");
  const replay = await issueMatchedRewards(rejectDb, rejectSpec);
  assert(replay.issued.length === 0 && replay.pending.length === 0, "a rejected reward is not issued again");
  assert(replay.skipped.some((row) => row.reason === "REWARD_CLOSED" && row.status === "REJECTED"), "a rejected replay is closed");
  assert(rejectDb.state.rewards.length === 1 && rejectDb.state.budgets[0].issuedAmount === "0.00", "a rejected replay does not reserve the budget again");

  const failing = store();
  const failingInput = input(failing, {
    slot: "buyer",
    recipientRole: "BUYER",
    rewardType: "FIXED_COUPON",
    amount: "20.00",
  });
  failing.state.failCoupon = true;
  let thrown = false;
  try {
    await failing.$transaction((tx) => issueMatchedRewards(tx, {
      ...failingInput,
      couponWriter: failing.couponWriter,
    }));
  } catch (error) {
    thrown = error.message === "coupon database unavailable";
  }
  assert(thrown, "coupon creation failure is returned to the caller");
  assert(failing.state.rewards.length === 0 && failing.state.budgets[0].issuedAmount === "0.00", "coupon failure rolls the reward back");

  const disabled = store();
  const off = await issueMatchedRewards(disabled, input(disabled, {
    slot: "buyer",
    recipientRole: "BUYER",
    rewardType: "FIXED_COUPON",
    amount: "20.00",
  }, flagsOff()));
  assert(off.issued.length === 0 && off.skipped[0].reason === "ISSUANCE_DISABLED", "missing or off issuance creates nothing");
  assert(disabled.state.rewards.length === 0, "fail-closed issuance writes no reward");
}

async function testLedger() {
  const db = store();
  const issued = await issueMatchedRewards(db, input(db, {
    slot: "points",
    recipientRole: "TRIGGER_USER",
    rewardType: "POINTS",
    amount: "40.00",
    expiryDays: 1,
  }));
  const reward = db.state.rewards[0];
  const atIssue = new Date("2026-11-17T13:00:00.000Z");
  await redeemReward(db, {
    rewardId: reward.id,
    amount: "10.00",
    actorId: "admin-1",
    idempotencyKey: "use-1",
    flags: { redemption: true },
    now: atIssue,
  });
  const repeat = await redeemReward(db, {
    rewardId: reward.id,
    amount: "10.00",
    actorId: "admin-1",
    idempotencyKey: "use-1",
    flags: { redemption: true },
    now: atIssue,
  });
  assert(repeat.duplicate === true && db.state.entries.length === 2, "repeated redemption does not debit twice");
  assert(await balanceOf(db, reward.id) === 30, "balance is issue minus redemption");
  let refused = false;
  try {
    await redeemReward(db, {
      rewardId: reward.id,
      amount: "50.00",
      actorId: "admin-1",
      idempotencyKey: "use-2",
      flags: { redemption: true },
      now: atIssue,
    });
  } catch (error) {
    refused = error.code === "INSUFFICIENT_CREDIT";
  }
  assert(refused && db.state.entries.length === 2, "a debit below zero is refused");
  let closed = false;
  try {
    await redeemReward(db, {
      rewardId: reward.id,
      amount: "1.00",
      actorId: "admin-1",
      idempotencyKey: "use-3",
      flags: flagsOff(),
      now: atIssue,
    });
  } catch (error) {
    closed = error.code === "REDEMPTION_DISABLED";
  }
  assert(closed, "redemption stays off when the switch is missing");
  reward.expiresAt = new Date("2026-11-17T00:00:00.000Z");
  const expired = await expireDueRewards(db, { now: new Date("2026-11-18T00:00:00.000Z"), actorId: "admin-1" });
  const expiredAgain = await expireDueRewards(db, { now: new Date("2026-11-18T00:00:00.000Z"), actorId: "admin-1" });
  assert(expired.length === 1 && expiredAgain.length === 0, "expiry runs once");
  assert(await balanceOf(db, reward.id) === 0, "expiry clears the remaining credit");
  const ledgerSource = fs.readFileSync(path.join(__dirname, "../modules/incentive-engine/rewards/ledger.js"), "utf8");
  assert(!ledgerSource.includes(".update(") && !ledgerSource.includes(".delete("), "application ledger code has no update or delete");
  const migration = fs.readFileSync(path.join(__dirname, "../prisma/migrations/20261117233000_incentive_ledger_guard/migration.sql"), "utf8");
  assert(migration.includes("BEFORE UPDATE") && migration.includes("BEFORE DELETE") && migration.includes("would make the balance negative"), "database guard rejects mutation and a negative balance");
  assert(migration.includes('FROM "IncentiveReward"') && migration.includes("FOR UPDATE"), "insert guard locks the reward row before the balance sum");
  assert(migration.includes("ISSUE amount must be positive") && migration.includes("REDEEM amount must be negative") && migration.includes("EXPIRE amount must be negative"), "insert guard checks the sign of each supported entry");
  assert(migration.includes("entry type is not supported"), "insert guard rejects an unsupported entry type");
  for (const attempt of [
    { entryType: "ISSUE", amount: "-1.00", code: "LEDGER_AMOUNT_INVALID" },
    { entryType: "REDEEM", amount: "1.00", code: "LEDGER_AMOUNT_INVALID" },
    { entryType: "EXPIRE", amount: "1.00", code: "LEDGER_AMOUNT_INVALID" },
    { entryType: "ADJUST", amount: "1.00", code: "LEDGER_ENTRY_UNSUPPORTED" },
    { entryType: "REVERSE", amount: "-1.00", code: "LEDGER_ENTRY_UNSUPPORTED" },
  ]) {
    let code = null;
    try {
      await postEntry(db, {
        rewardId: reward.id,
        entryType: attempt.entryType,
        amount: attempt.amount,
        idempotencyKey: `bad-${attempt.entryType}`,
      });
    } catch (error) {
      code = error.code;
    }
    assert(code === attempt.code, `${attempt.entryType} ${attempt.amount} is rejected`);
  }
  assert(db.state.entries.length === 3, "a rejected entry is not posted");
  let bad = false;
  try {
    await postEntry(db, { rewardId: reward.id, entryType: "REDEEM", amount: "-1.00", idempotencyKey: "too-much" });
  } catch (error) {
    bad = error.code === "INSUFFICIENT_CREDIT";
  }
  assert(bad, "a posted debit cannot take the derived balance below zero");
}

async function testConcurrencyAndIssuanceFlag() {
  const debits = store();
  const issued = await issueMatchedRewards(debits, input(debits, {
    slot: "points",
    recipientRole: "TRIGGER_USER",
    rewardType: "POINTS",
    amount: "10.00",
  }));
  const rewardId = issued.issued[0].id;
  const attempts = await Promise.allSettled([
    redeemReward(debits, { rewardId, amount: "6.00", actorId: "admin-1", idempotencyKey: "debit-a", flags: { redemption: true } }),
    redeemReward(debits, { rewardId, amount: "6.00", actorId: "admin-1", idempotencyKey: "debit-b", flags: { redemption: true } }),
  ]);
  const fulfilled = attempts.filter((row) => row.status === "fulfilled");
  const rejected = attempts.filter((row) => row.status === "rejected");
  assert(fulfilled.length === 1 && rejected.length === 1, "one of two concurrent debits is refused");
  assert(rejected[0].reason.code === "INSUFFICIENT_CREDIT", "the losing debit reports an insufficient balance");
  assert(await balanceOf(debits, rewardId) === 4, "concurrent debits leave a balance of 4");

  const otherReward = await issueMatchedRewards(debits, input(debits, {
    slot: "other",
    recipientRole: "TRIGGER_USER",
    rewardType: "POINTS",
    amount: "10.00",
  }));
  await redeemReward(debits, {
    rewardId: otherReward.issued[0].id,
    amount: "6.00",
    actorId: "admin-1",
    idempotencyKey: "other-debit",
    flags: { redemption: true },
  });
  assert(await balanceOf(debits, otherReward.issued[0].id) === 4, "a different reward keeps its own balance");

  const race = store();
  race.state.budgets.push({ id: "budget-1", versionId: "version-1", amountCap: "20.00", issuedAmount: "10.00" });
  race.state.versions.push({
    id: "version-1",
    snapshot: {
      budget: { amountCap: "20.00" },
      rewards: [{ slot: "held", recipientRole: "TRIGGER_USER", rewardType: "PROMOTIONAL_CREDIT", amount: "10.00" }],
    },
  });
  race.state.rewards.push({
    id: "reward-held",
    campaignVersionId: "version-1",
    rewardSlot: "held",
    recipientUserId: "buyer-1",
    sourceEventId: "event-held",
    status: "PENDING_APPROVAL",
    amount: "10.00",
    idempotencyKey: "version-1:event-held:buyer-1:held",
  });
  const fresh = {
    event: { id: "event-new", type: "ORDER_QUALIFIED", userId: "buyer-1", entityId: "order-2" },
    matches: [{ campaignId: "campaign-1", passed: true }],
    campaigns: [campaign({
      reward: { slot: "fresh", recipientRole: "TRIGGER_USER", rewardType: "PROMOTIONAL_CREDIT", amount: "15.00" },
    })],
    flags: { issuance: true },
    now: new Date("2026-11-17T12:00:00.000Z"),
    couponWriter: race.couponWriter,
  };
  fresh.campaigns[0].version.snapshot.budget.amountCap = "20.00";
  const [rejection, issuance] = await Promise.allSettled([
    rejectReward(race, { rewardId: "reward-held", actorId: "admin-1", reason: "No" }),
    issueMatchedRewards(race, fresh),
  ]);
  assert(rejection.status === "fulfilled" && rejection.value.status === "REJECTED", "rejection completes beside issuance");
  const again = await rejectReward(race, { rewardId: "reward-held", actorId: "admin-1" });
  assert(again.status === "REJECTED", "a second rejection does not run the release again");
  const amount = race.state.budgets[0].issuedAmount;
  const created = race.state.rewards.filter((row) => row.rewardSlot === "fresh");
  assert(amount === "15.00" || amount === "0.00", "budget is either the new credit or fully released");
  assert(created.length === (amount === "15.00" ? 1 : 0), "a new credit exists only when the released budget can hold it");
  assert(issuance.status === "fulfilled", "issuance returns instead of overwriting the budget");

  const blocked = store();
  const held = await issueMatchedRewards(blocked, input(blocked, {
    slot: "buyer",
    recipientRole: "BUYER",
    rewardType: "FIXED_COUPON",
    amount: "20.00",
    requireAdminApproval: true,
  }));
  blocked.state.issuanceValue = "\t\ntrue\r\n";
  const whitespaceApproved = await approveReward(blocked, {
    rewardId: held.pending[0].id,
    actorId: "admin-1",
    couponWriter: blocked.couponWriter,
  });
  assert(whitespaceApproved.status === "ISSUED" && blocked.state.coupons.length === 1, "space, tab, and newline around true allow approval");
  const secondHeld = await issueMatchedRewards(blocked, input(blocked, {
    slot: "second",
    recipientRole: "BUYER",
    rewardType: "FIXED_COUPON",
    amount: "10.00",
    requireAdminApproval: true,
  }));
  for (const value of [null, "false", "TRUE", "\tTRUE\n", "true\nfalse", "\u00A0true"]) {
    blocked.state.issuanceValue = value;
    blocked.state.settingError = null;
    let code = null;
    try {
      await approveReward(blocked, { rewardId: secondHeld.pending[0].id, actorId: "admin-1", couponWriter: blocked.couponWriter });
    } catch (error) {
      code = error.code;
    }
    assert(code === "ISSUANCE_DISABLED", "approval is refused unless issuance is exactly true");
  }
  blocked.state.settingError = "database unavailable";
  let failed = null;
  try {
    await approveReward(blocked, { rewardId: secondHeld.pending[0].id, actorId: "admin-1", couponWriter: blocked.couponWriter });
  } catch (error) {
    failed = error.code;
  }
  assert(failed === "ISSUANCE_DISABLED" && blocked.state.coupons.length === 1, "a flag read error does not approve another reward");
  assert(blocked.state.rewards.find((row) => row.rewardSlot === "second").status === "PENDING_APPROVAL", "a refused approval leaves the reward pending");
}

async function testRewardBoundaries() {
  const capped = store();
  const cappedSpec = input(capped, {
    slot: "credit",
    recipientRole: "TRIGGER_USER",
    rewardType: "PROMOTIONAL_CREDIT",
    amount: "15.00",
  });
  cappedSpec.campaigns[0].version.snapshot.budget.maxRewardAmount = "10.00";
  const overCap = await issueMatchedRewards(capped, cappedSpec);
  assert(overCap.issued.length === 0 && overCap.skipped.some((row) => row.reason === "REWARD_AMOUNT_EXCEEDS_CAP"), "a reward above the configured maximum is not issued");
  assert(capped.state.rewards.length === 0 && capped.state.budgets[0].issuedAmount === "0.00", "an over-cap reward does not reserve budget");

  const percent = store();
  const percentSpec = input(percent, {
    slot: "buyer",
    recipientRole: "BUYER",
    rewardType: "PERCENTAGE_COUPON",
    amount: "10.00",
    maxDiscount: "50.00",
    requireAdminApproval: true,
  });
  const pendingPercent = await issueMatchedRewards(percent, percentSpec);
  assert(percent.state.budgets[0].issuedAmount === "50.00", "pending percentage reserves the maximum discount");
  const released = await rejectReward(percent, { rewardId: pendingPercent.pending[0].id, actorId: "admin-1" });
  assert(released.status === "REJECTED" && percent.state.budgets[0].issuedAmount === "0.00", "rejecting a percentage coupon releases the reserved maximum");

  const missing = store();
  const missingSpec = input(missing, {
    slot: "credit",
    recipientRole: "TRIGGER_USER",
    rewardType: "PROMOTIONAL_CREDIT",
    amount: "15.00",
    requireAdminApproval: true,
  });
  const pendingCredit = await issueMatchedRewards(missing, missingSpec);
  missing.state.versions = [];
  let missingCode = null;
  try {
    await rejectReward(missing, { rewardId: pendingCredit.pending[0].id, actorId: "admin-1" });
  } catch (error) {
    missingCode = error.code;
  }
  assert(missingCode === "REWARD_DEFINITION_MISSING", "rejection refuses a reward whose definition is gone");
  assert(missing.state.rewards[0].status === "PENDING_APPROVAL" && missing.state.budgets[0].issuedAmount === "15.00", "a missing definition does not release an guessed amount");

  const credit = store();
  const issued = await issueMatchedRewards(credit, input(credit, {
    slot: "points",
    recipientRole: "TRIGGER_USER",
    rewardType: "POINTS",
    amount: "40.00",
    expiryDays: 10,
  }));
  const reward = credit.state.rewards[0];
  await redeemReward(credit, {
    rewardId: reward.id,
    amount: "10.00",
    actorId: "admin-1",
    idempotencyKey: "use-a",
    flags: { redemption: true },
    now: new Date("2026-11-17T12:00:00.000Z"),
  });
  await redeemReward(credit, {
    rewardId: reward.id,
    amount: "5.00",
    actorId: "admin-1",
    idempotencyKey: "use-b",
    flags: { redemption: true },
    now: new Date("2026-11-17T12:00:00.000Z"),
  });
  const repeated = await redeemReward(credit, {
    rewardId: reward.id,
    amount: "10.00",
    actorId: "admin-1",
    idempotencyKey: "use-a",
    flags: { redemption: true },
    now: new Date("2026-11-17T12:00:00.000Z"),
  });
  assert(repeated.duplicate === true && Number(repeated.redemption.amount) === 10, "a repeated redemption returns its own row");
  assert(credit.state.redemptions.length === 2 && credit.state.entries.length === 3, "a repeated redemption does not add a row");
  let conflict = null;
  try {
    await redeemReward(credit, {
      rewardId: reward.id,
      amount: "4.00",
      actorId: "admin-1",
      idempotencyKey: "use-a",
      flags: { redemption: true },
      now: new Date("2026-11-17T12:00:00.000Z"),
    });
  } catch (error) {
    conflict = error.code;
  }
  assert(conflict === "IDEMPOTENCY_CONFLICT" && credit.state.entries.length === 3, "the same redemption key cannot debit a different amount");
  reward.expiresAt = new Date("2026-11-01T00:00:00.000Z");
  let expiredCode = null;
  try {
    await redeemReward(credit, {
      rewardId: reward.id,
      amount: "1.00",
      actorId: "admin-1",
      idempotencyKey: "after-expiry",
      flags: { redemption: true },
      now: new Date("2026-11-17T12:00:00.000Z"),
    });
  } catch (error) {
    expiredCode = error.code;
  }
  assert(expiredCode === "REWARD_EXPIRED" && credit.state.entries.length === 3, "expired credit cannot be redeemed");

  const couponDb = store();
  const coupon = await issueMatchedRewards(couponDb, input(couponDb, {
    slot: "buyer",
    recipientRole: "BUYER",
    rewardType: "FIXED_COUPON",
    amount: "20.00",
  }));
  let couponCode = null;
  try {
    await redeemReward(couponDb, {
      rewardId: coupon.issued[0].id,
      amount: "20.00",
      actorId: "admin-1",
      idempotencyKey: "coupon",
      flags: { redemption: true },
    });
  } catch (error) {
    couponCode = error.code;
  }
  assert(couponCode === "COUPON_REDEMPTION_UNCHANGED" && couponDb.state.redemptions.length === 0, "coupon rewards stay on the coupon path");

  const owned = store();
  const ownedIssue = await issueMatchedRewards(owned, input(owned, {
    slot: "points",
    recipientRole: "TRIGGER_USER",
    rewardType: "POINTS",
    amount: "10.00",
    expiryDays: 10,
  }));
  owned.order = {
    async findUnique({ where }) {
      if (where.id === "order-1") return { id: "order-1", buyerId: "buyer-1" };
      if (where.id === "order-2") return { id: "order-2", buyerId: "buyer-2" };
      return null;
    },
  };
  let mismatch = null;
  try {
    await redeemReward(owned, {
      rewardId: ownedIssue.issued[0].id,
      amount: "4.00",
      orderId: "order-2",
      actorId: "admin-1",
      idempotencyKey: "wrong-order",
      flags: { redemption: true },
      now: new Date("2026-11-17T12:00:00.000Z"),
    });
  } catch (error) {
    mismatch = error.code;
  }
  assert(mismatch === "REWARD_ORDER_MISMATCH" && owned.state.entries.length === 1, "credit cannot be attached to another buyer's order");
  const applied = await redeemReward(owned, {
    rewardId: ownedIssue.issued[0].id,
    amount: "4.00",
    orderId: "order-1",
    actorId: "admin-1",
    idempotencyKey: "right-order",
    flags: { redemption: true },
    now: new Date("2026-11-17T12:00:00.000Z"),
  });
  assert(applied.redemption.orderId === "order-1" && applied.reward.status === "PARTIALLY_REDEEMED", "credit redemption records the recipient's order");

  const race = store();
  const raced = await issueMatchedRewards(race, input(race, {
    slot: "points",
    recipientRole: "TRIGGER_USER",
    rewardType: "POINTS",
    amount: "10.00",
    expiryDays: 1,
  }));
  race.state.rewards[0].expiresAt = new Date("2026-11-17T12:00:00.000Z");
  const redeemAt = new Date("2026-11-17T11:00:00.000Z");
  const expireAt = new Date("2026-11-17T13:00:00.000Z");
  const [redeemed, expired] = await Promise.allSettled([
    redeemReward(race, {
      rewardId: raced.issued[0].id,
      amount: "10.00",
      actorId: "admin-1",
      idempotencyKey: "race",
      flags: { redemption: true },
      now: redeemAt,
    }),
    expireDueRewards(race, { now: expireAt, actorId: "admin-1" }),
  ]);
  const expireCount = expired.status === "fulfilled" ? expired.value.length : -1;
  const redeemCode = redeemed.status === "rejected" ? redeemed.reason.code : null;
  assert(expired.status === "fulfilled", "expiry finishes beside redemption");
  assert(
    (redeemed.status === "fulfilled" && expireCount === 0) || (redeemCode === "REWARD_NOT_REDEEMABLE" && expireCount === 1),
    `redemption and expiry do not both close the same credit (${redeemed.status}:${redeemCode}:${expireCount}:${race.state.rewards[0].status})`
  );
  assert(await balanceOf(race, raced.issued[0].id) === 0, "the redemption and expiry race leaves no spendable credit");
  assert(race.state.entries.filter((row) => row.entryType !== "ISSUE").length === 1, "the race posts one debit");
  assert(race.state.audits.filter((row) => row.action === "REWARD_REDEEMED" || row.action === "REWARD_EXPIRED").length === 1, "the race writes one terminal audit");
}

async function testAdminGate() {
  const calls = { approve: 0 };
  const app = express();
  app.use(express.json());
  app.use((req, res, next) => {
    req.user = { id: "admin-1", role: req.header("x-role") || "admin" };
    next();
  });
  app.use("/admin", createRewardsRouter({
    prisma: {
      incentiveReward: { async findMany() { return []; } },
      incentiveSetting: { async findMany() { return []; } },
      $transaction(work) { calls.approve += 1; return work({}); },
    },
    requireUser: (req, res, next) => next(),
    requireAdmin: (req, res, next) => next(),
    requireSuperAdmin: (req, res, next) => {
      if (req.user.role !== "super_admin") return res.status(403).json({ error: "Super admin only" });
      return next();
    },
  }));
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, resolve));
  try {
    const deniedPaths = [
      "/admin/rewards/reward-1/approve",
      "/admin/rewards/reward-1/reject",
      "/admin/rewards/reward-1/redeem",
      "/admin/rewards/expire-due",
    ];
    for (const path of deniedPaths) {
      const denied = await new Promise((resolve, reject) => {
        const req = http.request({
          hostname: "127.0.0.1",
          port: server.address().port,
          path,
          method: "POST",
          headers: { "x-role": "admin", "Content-Length": "2" },
        }, (res) => {
          res.resume();
          res.on("end", () => resolve(res.statusCode));
        });
        req.on("error", reject);
        req.end("{}");
      });
      assert(denied === 403, `${path} must stay super-admin only`);
    }
    assert(calls.approve === 0, "portal admin cannot open a reward transaction");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
  const processSource = fs.readFileSync(path.join(__dirname, "../modules/incentive-engine/events/process.js"), "utf8");
  assert(processSource.includes("projectRewards"), "processed events hand rewards to the finish transaction");
  assert(!processSource.includes("incentiveReward.create") && !processSource.includes("incentiveLedgerEntry.create"), "event processing does not write reward rows itself");
}

async function testCouponParser() {
  const coupons = [];
  const members = [];
  const client = {
    coupon: {
      async create({ data }) {
        if (coupons.some((row) => row.code === data.code)) {
          const error = new Error("Unique");
          error.code = "P2002";
          throw error;
        }
        const row = { id: "coupon-parser", ...data };
        coupons.push(row);
        return row;
      },
    },
    couponEligibleUser: {
      async createMany({ data }) {
        members.push(...data);
        return { count: data.length };
      },
    },
  };
  const created = await createAssignedCoupon(client, {
    code: "SBTESTCODE000001",
    name: "SocietyEats reward",
    discountType: "FIXED",
    discountValue: 20,
    minimumOrderValue: 0,
    validFrom: new Date("2026-11-17T00:00:00.000Z"),
    validUntil: new Date("2026-12-17T00:00:00.000Z"),
    audienceType: "SELECTED_USERS",
    userIds: ["buyer-1"],
    status: "ACTIVE",
    usagePerBuyerLimit: 1,
    totalUsageLimit: 1,
  });
  assert(created.id === "coupon-parser" && members[0].userId === "buyer-1", "assigned coupon uses the existing coupon parser");
  let duplicate = false;
  try {
    await createAssignedCoupon(client, {
      code: "SBTESTCODE000001",
      name: "SocietyEats reward",
      discountType: "FIXED",
      discountValue: 20,
      minimumOrderValue: 0,
      validFrom: new Date("2026-11-17T00:00:00.000Z"),
      validUntil: new Date("2026-12-17T00:00:00.000Z"),
      audienceType: "SELECTED_USERS",
      status: "ACTIVE",
    });
  } catch (error) {
    duplicate = error.statusCode === 409;
  }
  assert(duplicate && coupons.length === 1, "duplicate coupon code is rejected");
}

async function main() {
  await testFixedAndPercentage();
  await testCreditDuplicateAndBudget();
  await testApprovalFailureAndFlags();
  await testConcurrencyAndIssuanceFlag();
  await testLedger();
  await testRewardBoundaries();
  await testAdminGate();
  await testCouponParser();
  console.log("incentive rewards ok");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
