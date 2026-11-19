process.env.DATABASE_URL = "postgresql://postgres@127.0.0.1:5432/societybites_incentive_unit";
process.env.DIRECT_URL = process.env.DATABASE_URL;

const fs = require("fs");
const path = require("path");
const http = require("http");
const express = require("express");
const { createMyRewardsRouter } = require("../modules/incentive-engine/routes/myRewards");
const { createRewardsRouter } = require("../modules/incentive-engine/routes/adminRewards");
const { reconcileBudget, listVisibleOffers } = require("../modules/incentive-engine/rewards/read");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const rewards = [
  {
    id: "reward-a",
    campaignVersionId: "version-1",
    rewardSlot: "credit",
    recipientUserId: "user-a",
    sourceEventId: "event-1",
    referralId: null,
    couponId: null,
    status: "ISSUED",
    amount: "10.00",
    currency: "INR",
    expiresAt: null,
    idempotencyKey: "reward-a-key",
    createdAt: new Date("2026-11-17T10:00:00.000Z"),
  },
  {
    id: "reward-coupon",
    campaignVersionId: "version-1",
    rewardSlot: "coupon",
    recipientUserId: "user-a",
    sourceEventId: "event-2",
    referralId: null,
    couponId: "coupon-1",
    status: "ISSUED",
    amount: "25.00",
    currency: "INR",
    expiresAt: null,
    idempotencyKey: "reward-coupon-key",
    createdAt: new Date("2026-11-17T09:00:00.000Z"),
  },
  {
    id: "reward-b",
    campaignVersionId: "version-1",
    rewardSlot: "points",
    recipientUserId: "user-b",
    sourceEventId: "event-3",
    referralId: null,
    couponId: null,
    status: "ISSUED",
    amount: "5.00",
    currency: "INR",
    expiresAt: null,
    idempotencyKey: "reward-b-key",
    createdAt: new Date("2026-11-17T08:00:00.000Z"),
  },
];

const definitions = [
  { versionId: "version-1", slot: "credit", rewardType: "PROMOTIONAL_CREDIT" },
  { versionId: "version-1", slot: "coupon", rewardType: "FIXED_COUPON" },
  { versionId: "version-1", slot: "points", rewardType: "POINTS" },
];

const ledger = [
  { id: "ledger-1", rewardId: "reward-a", entryType: "ISSUE", amount: "10.00", currency: "INR", reason: "PROMOTIONAL_CREDIT", idempotencyKey: "issue-a", createdAt: new Date("2026-11-17T10:00:00.000Z") },
  { id: "ledger-2", rewardId: "reward-a", entryType: "REDEEM", amount: "-4.00", currency: "INR", reason: "redeem", idempotencyKey: "redeem-a", createdAt: new Date("2026-11-17T11:00:00.000Z") },
  { id: "ledger-3", rewardId: "reward-b", entryType: "ISSUE", amount: "5.00", currency: "INR", reason: "POINTS", idempotencyKey: "issue-b", createdAt: new Date("2026-11-17T12:00:00.000Z") },
];

function matches(row, where) {
  if (!where) return true;
  return Object.entries(where).every(([key, value]) => {
    if (key === "OR") return value.some((part) => matches(row, part));
    if (key === "AND") return value.every((part) => matches(row, part));
    if (key === "reward") return matches(row.reward, value);
    if (value && typeof value === "object" && Array.isArray(value.in)) return value.in.includes(row[key]);
    return row[key] === value;
  });
}

function ordered(rows, orderBy) {
  const spec = Array.isArray(orderBy) ? orderBy : [orderBy || { createdAt: "desc" }];
  return [...rows].sort((left, right) => {
    for (const part of spec) {
      const [key, direction] = Object.entries(part)[0];
      const leftValue = left[key] instanceof Date ? left[key].getTime() : left[key];
      const rightValue = right[key] instanceof Date ? right[key].getTime() : right[key];
      if (leftValue === rightValue) continue;
      const result = leftValue < rightValue ? -1 : 1;
      return direction === "desc" ? -result : result;
    }
    return 0;
  });
}

function pick(row, select) {
  if (!select) return row;
  const copy = {};
  for (const key of Object.keys(select)) if (select[key]) copy[key] = row[key];
  return copy;
}

function page(rows, args) {
  let list = ordered(rows, args.orderBy);
  if (args.cursor && args.cursor.id) {
    const index = list.findIndex((row) => row.id === args.cursor.id);
    list = index >= 0 ? list.slice(index + (args.skip || 0)) : [];
  }
  if (args.take) list = list.slice(0, args.take);
  return list;
}

function rewardClient() {
  return {
    incentiveReward: {
      async findMany(args = {}) {
        return page(rewards.filter((row) => matches(row, args.where)), args).map((row) => pick(row, args.select));
      },
      async findUnique() {
        return null;
      },
      async count({ where } = {}) {
        return rewards.filter((row) => matches(row, where)).length;
      },
      async groupBy({ where } = {}) {
        const grouped = new Map();
        for (const row of rewards.filter((item) => matches(item, where))) {
          const key = `${row.campaignVersionId}:${row.rewardSlot}`;
          const current = grouped.get(key) || {
            campaignVersionId: row.campaignVersionId,
            rewardSlot: row.rewardSlot,
            _count: { _all: 0 },
          };
          current._count._all += 1;
          grouped.set(key, current);
        }
        return [...grouped.values()];
      },
    },
    incentiveRewardDefinition: {
      async findMany(args = {}) {
        return definitions.filter((row) => matches(row, args.where)).map((row) => pick(row, args.select));
      },
    },
    incentiveLedgerEntry: {
      async findMany(args = {}) {
        const rows = ledger.map((entry) => ({
          ...entry,
          reward: rewards.find((row) => row.id === entry.rewardId),
        }));
        return page(rows.filter((row) => matches(row, args.where)), args).map((row) => {
          const picked = pick(row, args.select);
          if (args.include && args.include.reward) picked.reward = row.reward;
          if (!args.select) return { ...row };
          return picked;
        });
      },
    },
    incentiveCampaign: {
      async count({ where } = {}) {
        const campaigns = [{ status: "ACTIVE" }, { status: "DRAFT" }];
        return campaigns.filter((row) => matches(row, where)).length;
      },
    },
    incentiveReferral: {
      async count({ where } = {}) {
        const referrals = [{ status: "QUALIFIED" }, { status: "ATTRIBUTED" }];
        return referrals.filter((row) => matches(row, where)).length;
      },
    },
    incentiveEvent: {
      async findMany() {
        return [{
          id: "event-row",
          eventId: "USER_REGISTERED:user-a",
          schemaVersion: 1,
          type: "USER_REGISTERED",
          entityType: "User",
          entityId: "user-a",
          userId: "user-a",
          occurredAt: new Date("2026-11-17T07:00:00.000Z"),
          payload: {},
          status: "PENDING",
          attempts: 0,
        }];
      },
    },
    incentiveSetting: { async findMany() { return []; } },
    $transaction(work) {
      return work({});
    },
  };
}

function listen(app) {
  const server = http.createServer(app);
  return new Promise((resolve) => server.listen(0, () => resolve(server)));
}

function request(server, { method = "GET", path: requestPath, role = "admin", user = "user-a" }) {
  return new Promise((resolve, reject) => {
    const req = http.request({
      hostname: "127.0.0.1",
      port: server.address().port,
      path: requestPath,
      method,
      headers: { "x-role": role, "x-user": user },
    }, (res) => {
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => {
        const text = Buffer.concat(chunks).toString("utf8");
        resolve({ status: res.statusCode, body: text ? JSON.parse(text) : null });
      });
    });
    req.on("error", reject);
    req.end();
  });
}

async function main() {
  const source = fs.readFileSync(path.join(__dirname, "../modules/incentive-engine/routes/myRewards.js"), "utf8");
  assert(!source.includes("req.query.userId") && !source.includes("req.query.recipientUserId"), "caller routes do not read a client user id");
  assert(!source.includes("req.body"), "caller reward routes are read-only");

  const flagsSource = fs.readFileSync(path.join(__dirname, "../modules/incentive-engine/routes/flags.js"), "utf8");
  assert(!flagsSource.includes("router.put") && !flagsSource.includes("router.post") && !flagsSource.includes("router.patch"), "flag routes stay read-only");

  const app = express();
  app.use((req, res, next) => {
    req.user = { id: req.header("x-user") || "user-a", role: req.header("x-role") || "admin" };
    next();
  });
  const client = rewardClient();
  const guard = (req, res, next) => next();
  const superGuard = (req, res, next) => {
    if (req.user.role !== "super_admin") return res.status(403).json({ error: "Super admin only" });
    return next();
  };
  app.use(createMyRewardsRouter({ prisma: client, requireUser: guard }));
  app.use("/admin", createRewardsRouter({
    prisma: client,
    requireUser: guard,
    requireAdmin: guard,
    requireSuperAdmin: superGuard,
  }));
  const server = await listen(app);
  try {
    const own = await request(server, { path: "/rewards?recipientUserId=user-b&userId=user-b", user: "user-a" });
    assert(own.status === 200, "own rewards respond");
    assert(own.body.rewards.length === 2, "query user id does not widen the caller list");
    assert(own.body.rewards.every((row) => row.recipientUserId === "user-a"), "every reward belongs to the caller");
    const credit = own.body.rewards.find((row) => row.rewardSlot === "credit");
    const coupon = own.body.rewards.find((row) => row.rewardSlot === "coupon");
    assert(credit.rewardType === "PROMOTIONAL_CREDIT", "credit reward type comes from the definition");
    assert(coupon.rewardType === "FIXED_COUPON", "coupon reward type comes from the definition");
    assert(own.body.balances.promotionalCredit === "6.00", "credit balance is the ledger sum");
    assert(own.body.balances.points === "0.00", "another user's points are not included");

    const history = await request(server, { path: "/rewards/history?limit=1&recipientUserId=user-b", user: "user-a" });
    assert(history.body.entries.length === 1 && history.body.nextCursor, "history is paginated");
    assert(history.body.entries.every((row) => row.recipientUserId === "user-a" && row.rewardId !== "reward-b"), "history stays on the caller");

    const overview = await request(server, { path: "/admin/overview", role: "admin" });
    assert(overview.status === 200, "portal admin can read the overview");
    assert(overview.body.campaigns.total === 2 && overview.body.campaigns.active === 1, "campaign counts");
    assert(overview.body.referrals.total === 2 && overview.body.referrals.qualified === 1, "referral counts");
    assert(overview.body.rewards.issued === 3 && overview.body.rewards.fixedCoupons === 1, "issued reward counts by type");
    assert(overview.body.rewards.promotionalCredits === 1 && overview.body.rewards.points === 1, "credit and points counts");
    assert(overview.body.recentEvents[0].type === "USER_REGISTERED", "recent events come from the event list");

    const ledgerPage = await request(server, { path: "/admin/ledger?userId=user-a&limit=1", role: "admin" });
    assert(ledgerPage.body.entries.length === 1 && ledgerPage.body.entries[0].recipientUserId === "user-a", "ledger filter uses the reward owner");
    assert(ledgerPage.body.nextCursor, "ledger page exposes the next cursor");
    const typed = await request(server, { path: "/admin/ledger?rewardType=POINTS", role: "admin" });
    assert(typed.body.entries.length === 1 && typed.body.entries[0].rewardType === "POINTS", "ledger can filter by reward type");

    const denied = await request(server, { method: "POST", path: "/admin/rewards/reward-a/approve", role: "admin" });
    assert(denied.status === 403, "portal admin still cannot approve");
    const reconciled = await reconcileBudget({
      incentiveCampaign: { async findUnique() { return { id: "camp-1" }; } },
      incentiveCampaignVersion: { async findMany() { return [{ id: "version-1" }]; } },
      incentiveBudget: { async findMany() { return [{ amountCap: "100.00", issuedAmount: "25.00" }]; } },
      incentiveReward: { async findMany() { return [{ id: "reward-a", status: "ISSUED" }, { id: "reward-r", status: "REJECTED" }]; } },
      incentiveLedgerEntry: { async findMany() { return [{ entryType: "ISSUE", amount: "10.00" }, { entryType: "REDEEM", amount: "-4.00" }]; } },
    }, "camp-1");
    assert(reconciled.configured === "100.00" && reconciled.reserved === "25.00" && reconciled.remaining === "75.00", "budget reconciliation explains the cap and reservation");
    assert(reconciled.ledger.issued === "10.00" && reconciled.ledger.redeemed === "-4.00", "ledger totals stay signed");
    assert(reconciled.rewards.REJECTED === 1 && reconciled.reversedRewards === 0, "rejection is counted and reversal is not invented");

    const offersOff = await request(server, { path: "/offers", role: "seller", user: "seller-1" });
    assert(offersOff.status === 200 && offersOff.body.reason === "ENGINE_OFF" && offersOff.body.offers.length === 0, "offers stay empty while the master switch is off");
    const offerClient = {
      incentiveSetting: { async findMany() { return [{ key: "master_enabled", value: "true" }]; } },
      incentiveCampaign: {
        async findMany() {
          return [
            { id: "buyer-camp", name: "Welcome", description: "First order", category: "PROMOTIONAL", status: "ACTIVE", currentVersionId: "v-b", endsAt: null, createdBy: "secret-admin" },
            { id: "seller-camp", name: "List a dish", description: "First listing", category: "LISTING", status: "ACTIVE", currentVersionId: "v-s", endsAt: null },
          ];
        },
      },
      incentiveCampaignVersion: {
        async findUnique({ where }) {
          if (where.id === "v-b") {
            return {
              id: "v-b",
              publishedAt: new Date("2026-11-17T00:00:00.000Z"),
              snapshot: {
                rewards: [{ slot: 1, recipientRole: "BUYER", rewardType: "FIXED_COUPON", amount: "20.00", expiryDays: 7, internalNote: "hidden" }],
                audiences: [{ kind: "ALL_USERS", payload: { phone: "999" } }],
                triggers: [{ eventType: "ORDER_QUALIFIED" }],
              },
            };
          }
          return {
            id: "v-s",
            publishedAt: new Date("2026-11-17T00:00:00.000Z"),
            snapshot: { rewards: [{ slot: 1, recipientRole: "SELLER", rewardType: "PROMOTIONAL_CREDIT", amount: "15.00" }], audiences: [], triggers: [] },
          };
        },
      },
    };
    const buyerOffers = await listVisibleOffers(offerClient, { role: "buyer" });
    assert(buyerOffers.offers.length === 1 && buyerOffers.offers[0].id === "buyer-camp", "buyers see buyer offers only");
    const buyerText = JSON.stringify(buyerOffers.offers[0]);
    assert(!buyerText.includes("secret-admin") && !buyerText.includes("999") && !buyerText.includes("hidden"), "buyer offers omit admin identity and audience payload");
    assert(buyerOffers.offers[0].qualifiesWhen.includes("completed"), "offers explain the completed-order rule");
    const sellerOffers = await listVisibleOffers(offerClient, { role: "seller" });
    assert(sellerOffers.offers.length === 1 && sellerOffers.offers[0].id === "seller-camp", "sellers see seller offers only");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
  console.log("incentive read ok");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
