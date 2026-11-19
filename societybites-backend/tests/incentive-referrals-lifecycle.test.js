/**
 * Referral attribution and qualification. No database connection.
 */
process.env.DATABASE_URL = "postgresql://postgres:local-test-not-used@127.0.0.1:5432/societybites_incentive_foundation";
process.env.DIRECT_URL = process.env.DATABASE_URL;

const fs = require("fs");
const path = require("path");
const { claimReferral } = require("../modules/incentive-engine/referrals/attribute");
const {
  approveReferral,
  disqualifyReferral,
  expireDueReferrals,
  projectProcessedReferral,
  reconcileReferral,
} = require("../modules/incentive-engine/referrals/qualify");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function expectError(work, status, code) {
  try {
    await work();
  } catch (error) {
    assert(error.statusCode === status, `expected HTTP ${status}, got ${error.statusCode || "none"}: ${error.message}`);
    if (code) assert(error.code === code, `expected ${code}, got ${error.code || "none"}`);
    return error;
  }
  throw new Error(`expected HTTP ${status}`);
}

function flags(overrides = {}) {
  return {
    master: true,
    referral: true,
    buyerReferral: true,
    sellerReferral: true,
    ...overrides,
  };
}

function policy(overrides = {}) {
  return {
    codeExpiresInDays: 30,
    qualificationWindowDays: 14,
    maxAttributionsPerReferrer: 2,
    maxQualifiedPerReferrer: 1,
    buyer: { maxAccountAgeHours: 72 },
    ...overrides,
  };
}

function createDb() {
  const state = {
    flags: flags(),
    codes: [],
    users: [],
    campaigns: [],
    versions: [],
    referrals: [],
    audits: [],
    buyerOrders: [],
    sellerBlocks: {},
    inserts: 0,
  };
  return {
    state,
    async readFlags() {
      return state.flags;
    },
    async findCode(code) {
      return state.codes.find((row) => row.code === code) || null;
    },
    async findUser(id) {
      return state.users.find((row) => row.id === id) || null;
    },
    async findCampaign(id) {
      return state.campaigns.find((row) => row.id === id) || null;
    },
    async findVersion(id) {
      return state.versions.find((row) => row.id === id) || null;
    },
    async findReferral(referredUserId, acquisitionKind) {
      return state.referrals.find((row) => row.referredUserId === referredUserId && row.acquisitionKind === acquisitionKind) || null;
    },
    async findReverse(referrerUserId, referredUserId) {
      return state.referrals.find((row) => row.referrerUserId === referredUserId && row.referredUserId === referrerUserId) || null;
    },
    async buyerHasQualifyingOrder(userId) {
      return state.buyerOrders.includes(userId);
    },
    async sellerBlocked(userId) {
      return state.sellerBlocks[userId] || null;
    },
    async lockCodes() {
      return [];
    },
    async countAttributions(referrerUserId, campaignVersionId, acquisitionKind) {
      return state.referrals.filter((row) => row.referrerUserId === referrerUserId && row.campaignVersionId === campaignVersionId && row.acquisitionKind === acquisitionKind).length;
    },
    async insertReferral(data) {
      state.inserts += 1;
      const clash = state.referrals.find((row) => row.referredUserId === data.referredUserId && row.acquisitionKind === data.acquisitionKind);
      if (clash) {
        const error = new Error("unique");
        error.code = "P2002";
        throw error;
      }
      const row = { id: `ref-${state.inserts}`, sellerEnabledAt: null, listingId: null, qualifyingOrderId: null, ...data };
      state.referrals.push(row);
      return row;
    },
    async audit(data) {
      state.audits.push(data);
    },
  };
}

function seed(db, { cap = 2, qualifiedCap = 1, category = "BUYER_ACQUISITION" } = {}) {
  db.state.users.push(
    { id: "referrer", role: "seller", suspended: false, createdAt: "2026-11-01T00:00:00.000Z" },
    { id: "buyer", role: "buyer", suspended: false, createdAt: "2026-11-17T00:00:00.000Z" },
    { id: "other", role: "buyer", suspended: false, createdAt: "2026-11-17T01:00:00.000Z" }
  );
  db.state.campaigns.push({ id: "camp", category, status: "ACTIVE" });
  db.state.versions.push({
    id: "ver",
    campaignId: "camp",
    publishedAt: "2026-11-01T00:00:00.000Z",
    snapshot: {
      category,
      endsAt: "2026-12-31T00:00:00.000Z",
      referralPolicy: policy({ maxAttributionsPerReferrer: cap, maxQualifiedPerReferrer: qualifiedCap }),
    },
  });
  db.state.codes.push({
    id: "code-1",
    code: "AAAAAAAAAAAAAAA1",
    userId: "referrer",
    audience: "BUYER",
    active: true,
    expiresAt: "2026-12-01T00:00:00.000Z",
    campaignId: "camp",
    campaignVersionId: "ver",
  });
}

const now = new Date("2026-11-17T02:00:00.000Z");

async function testAttribution() {
  const db = createDb();
  seed(db);
  const buyer = { id: "buyer", role: "buyer", createdAt: "2026-11-17T00:00:00.000Z" };
  const created = await claimReferral(db, { user: buyer, now, body: { code: "AAAAAAAAAAAAAAA1", acquisitionKind: "BUYER_ACQUISITION", referrerUserId: "intruder" } });
  assert(created.created === true, "attribution is created");
  assert(created.referral.referrerUserId === "referrer", "the referrer comes from the code");
  assert(db.state.inserts === 1, "one referral row is written");
  const again = await claimReferral(db, { user: buyer, now, body: { code: "AAAAAAAAAAAAAAA1", acquisitionKind: "BUYER_ACQUISITION" } });
  assert(again.created === false && again.referral.id === created.referral.id, "the same claim is idempotent");
  assert(db.state.audits.length === 1, "a replay does not write a second audit");

  db.state.codes.push({ ...db.state.codes[0], id: "code-2", code: "BBBBBBBBBBBBBBB2", userId: "other" });
  await expectError(
    () => claimReferral(db, { user: buyer, now, body: { code: "BBBBBBBBBBBBBBB2", acquisitionKind: "BUYER_ACQUISITION" } }),
    409,
    "REFERRER_ALREADY_SET"
  );

  const self = createDb();
  seed(self);
  self.state.codes[0].userId = "buyer";
  await expectError(
    () => claimReferral(self, { user: buyer, now, body: { code: "AAAAAAAAAAAAAAA1", acquisitionKind: "BUYER_ACQUISITION" } }),
    409,
    "SELF_REFERRAL"
  );

  const circle = createDb();
  seed(circle);
  circle.state.referrals.push({ id: "old", referrerUserId: "buyer", referredUserId: "referrer", acquisitionKind: "SELLER_ACQUISITION", codeId: "other-code" });
  await expectError(
    () => claimReferral(circle, { user: buyer, now, body: { code: "AAAAAAAAAAAAAAA1", acquisitionKind: "BUYER_ACQUISITION" } }),
    409,
    "CIRCULAR_REFERRAL"
  );

  const old = createDb();
  seed(old);
  await expectError(
    () => claimReferral(old, { user: { ...buyer, createdAt: "2026-01-01T00:00:00.000Z" }, now, body: { code: "AAAAAAAAAAAAAAA1", acquisitionKind: "BUYER_ACQUISITION" } }),
    409,
    "ACCOUNT_NOT_ELIGIBLE"
  );
  old.state.buyerOrders.push("buyer");
  old.state.users.find((row) => row.id === "buyer").createdAt = "2026-11-17T00:00:00.000Z";
  await expectError(
    () => claimReferral(old, { user: buyer, now, body: { code: "AAAAAAAAAAAAAAA1", acquisitionKind: "BUYER_ACQUISITION" } }),
    409,
    "PRIOR_ACTIVITY"
  );

  const capped = createDb();
  seed(capped, { cap: 1 });
  await claimReferral(capped, { user: buyer, now, body: { code: "AAAAAAAAAAAAAAA1", acquisitionKind: "BUYER_ACQUISITION" } });
  await expectError(
    () => claimReferral(capped, { user: { id: "other", role: "buyer", createdAt: "2026-11-17T01:00:00.000Z" }, now, body: { code: "AAAAAAAAAAAAAAA1", acquisitionKind: "BUYER_ACQUISITION" } }),
    409,
    "REFERRAL_LIMIT"
  );

  const off = createDb();
  seed(off);
  off.state.flags = flags({ buyerReferral: false });
  await expectError(
    () => claimReferral(off, { user: buyer, now, body: { code: "AAAAAAAAAAAAAAA1", acquisitionKind: "BUYER_ACQUISITION" } }),
    403,
    "REFERRAL_DISABLED"
  );
  assert(off.state.inserts === 0, "a disabled flag does not write a referral");

  const seller = createDb();
  seed(seller, { category: "SELLER_ACQUISITION" });
  seller.state.codes[0].audience = "SELLER";
  seller.state.versions[0].snapshot.referralPolicy = { codeExpiresInDays: 10, qualificationWindowDays: 30, seller: { maxAccountAgeHours: null } };
  seller.state.sellerBlocks.buyer = "PRIOR_SELLER_ACTIVITY";
  await expectError(
    () => claimReferral(seller, { user: buyer, now, body: { code: "AAAAAAAAAAAAAAA1", acquisitionKind: "SELLER_ACQUISITION" } }),
    409,
    "PRIOR_SELLER_ACTIVITY"
  );
}

function order(overrides = {}) {
  return {
    id: "order-1",
    buyerId: "buyer",
    status: "completed",
    paymentMethod: "upi",
    paymentStatus: "paid",
    paymentProvider: "direct_upi",
    completedAt: "2026-11-18T00:00:00.000Z",
    items: [{ listing: { sellerId: "seller", societyId: "society-1" } }],
    ...overrides,
  };
}

function referralRow(overrides = {}) {
  return {
    id: "ref-1",
    codeId: "code-1",
    campaignId: "camp",
    campaignVersionId: "ver",
    referrerUserId: "referrer",
    referredUserId: "buyer",
    acquisitionKind: "BUYER_ACQUISITION",
    status: "ATTRIBUTED",
    attributedAt: "2026-11-17T02:00:00.000Z",
    windowEndsAt: "2026-12-01T00:00:00.000Z",
    sellerEnabledAt: null,
    listingId: null,
    listingPublishedAt: null,
    qualifyingOrderId: null,
    qualifyingOrderAt: null,
    ...overrides,
  };
}

function createTx(referral, versionPolicy = policy()) {
  const audits = [];
  let current = { ...referral };
  return {
    audits,
    current: () => current,
    incentiveReferral: {
      async findMany() {
        return [current];
      },
      async findUnique() {
        return current;
      },
      async update({ data }) {
        current = { ...current, ...data };
        return current;
      },
      async count() {
        return current.status === "QUALIFIED" || current.status === "PENDING_REVIEW" ? 1 : 0;
      },
    },
    incentiveCampaignVersion: {
      async findUnique() {
        return { id: "ver", snapshot: { referralPolicy: versionPolicy, endsAt: "2026-12-31T00:00:00.000Z" } };
      },
    },
    incentiveAuditLog: {
      async create({ data }) {
        audits.push(data);
      },
    },
    async $queryRaw() {
      return [];
    },
  };
}

async function testQualification() {
  const buyerTx = createTx(referralRow(), policy({ maxQualifiedPerReferrer: null, requireAdminApproval: false }));
  await projectProcessedReferral(buyerTx, {
    event: { id: "event-1", type: "ORDER_QUALIFIED", entityId: "order-1", occurredAt: "2026-11-20T00:00:00.000Z", attempts: 1 },
    order: order(),
    flags: flags(),
    now: new Date("2026-12-20T00:00:00.000Z"),
  });
  assert(buyerTx.current().status === "QUALIFIED", "a delayed in-window order still qualifies");
  assert(buyerTx.current().qualifyingOrderAt.toISOString() === "2026-11-20T00:00:00.000Z", "qualification uses the order time");

  const late = createTx(referralRow());
  await projectProcessedReferral(late, {
    event: { id: "event-2", type: "ORDER_QUALIFIED", entityId: "order-2", occurredAt: "2027-01-01T00:00:00.000Z", attempts: 1 },
    order: order(),
    flags: flags(),
  });
  assert(late.current().status === "ATTRIBUTED", "an order outside the window does not qualify");

  const seller = createTx(referralRow({ referredUserId: "seller", acquisitionKind: "SELLER_ACQUISITION" }), policy({ maxQualifiedPerReferrer: null }));
  const sale = order({ buyerId: "buyer", items: [{ listing: { sellerId: "seller", societyId: "society-1" } }] });
  await projectProcessedReferral(seller, {
    event: { id: "sale", type: "ORDER_QUALIFIED", entityId: "order-1", userId: "seller", occurredAt: "2026-11-18T00:00:00.000Z", attempts: 1 },
    order: sale,
    flags: flags(),
  });
  assert(seller.current().status === "ATTRIBUTED", "a sale before the other seller milestones stays attributed");
  await projectProcessedReferral(seller, {
    event: { id: "list", type: "LISTING_PUBLISHED", entityId: "listing-2", userId: "seller", occurredAt: "2026-11-19T00:00:00.000Z", attempts: 1 },
    flags: flags(),
  });
  await projectProcessedReferral(seller, {
    event: { id: "list-earlier", type: "LISTING_PUBLISHED", entityId: "listing-1", userId: "seller", occurredAt: "2026-11-18T00:00:00.000Z", attempts: 1 },
    flags: flags(),
  });
  assert(seller.current().listingId === "listing-1", "the earliest in-window listing is kept");
  await projectProcessedReferral(seller, {
    event: { id: "terms", type: "USER_BECAME_SELLER", entityId: "seller", userId: "seller", occurredAt: "2026-11-17T03:00:00.000Z", attempts: 1 },
    flags: flags(),
  });
  assert(seller.current().status === "QUALIFIED", "seller qualification waits for every milestone");

  const capped = createTx(referralRow(), policy({ maxQualifiedPerReferrer: 1 }));
  capped.incentiveReferral.count = async () => 1;
  await projectProcessedReferral(capped, {
    event: { id: "event-cap", type: "ORDER_QUALIFIED", entityId: "order-1", occurredAt: "2026-11-20T00:00:00.000Z", attempts: 1 },
    order: order(),
    flags: flags(),
  });
  assert(capped.current().status === "ATTRIBUTED", "a qualified cap leaves the referral attributed");
  assert(capped.audits.some((row) => row.action === "REFERRAL_QUALIFICATION_SKIPPED"), "the cap skip is audited");

  const approval = createTx(referralRow(), policy({ maxQualifiedPerReferrer: null, requireAdminApproval: true }));
  await projectProcessedReferral(approval, {
    event: { id: "event-review", type: "ORDER_QUALIFIED", entityId: "order-1", occurredAt: "2026-11-20T00:00:00.000Z", attempts: 1 },
    order: order(),
    flags: flags(),
  });
  assert(approval.current().status === "PENDING_REVIEW", "approval holds qualification");
  await approveReferral(approval, { id: "ref-1", actorId: "admin" });
  assert(approval.current().status === "QUALIFIED", "super-admin approval qualifies");

  const reversed = createTx(referralRow({
    status: "QUALIFIED",
    qualifyingOrderId: "order-1",
    qualifyingOrderAt: "2026-11-20T00:00:00.000Z",
  }));
  const saved = await reconcileReferral(reversed, reversed.current(), {
    order: order({ status: "cancelled" }),
    now: new Date("2026-11-21T00:00:00.000Z"),
    actorId: "admin",
  });
  assert(saved.status === "ATTRIBUTED" && saved.qualifyingOrderId === null, "a failed order reverses qualification while the window is open");

  const expired = createTx(referralRow());
  const rows = await expireDueReferrals(expired, { now: new Date("2026-12-15T00:00:00.000Z"), actorId: "admin" });
  assert(rows.length === 1 && rows[0].status === "EXPIRED", "an open referral expires after its window");
  await disqualifyReferral(createTx(referralRow()), { id: "ref-1", actorId: "admin", reason: "fraud" });
}

function testBoundaries() {
  const processSource = fs.readFileSync(path.join(__dirname, "../modules/incentive-engine/events/process.js"), "utf8");
  const repositorySource = fs.readFileSync(path.join(__dirname, "../modules/incentive-engine/events/repository.js"), "utf8");
  const migration = fs.readFileSync(path.join(__dirname, "../prisma/migrations/20261117213000_incentive_referral_attribution/migration.sql"), "utf8");
  assert(!processSource.includes("incentiveReferral.create"), "event processing does not create referrals");
  assert(!processSource.includes("incentiveReward.create"), "event processing does not issue rewards");
  assert(repositorySource.includes("patch.projectReferral"), "referral projection runs inside finish");
  assert(migration.includes("IncentiveReferral_users_distinct"), "self-referral is rejected by the database");
  assert(!/ALTER TABLE "(User|Order|Listing|Coupon|AppSetting)"/i.test(migration), "referral migration does not alter core tables");
  const attribute = fs.readFileSync(path.join(__dirname, "../modules/incentive-engine/referrals/attribute.js"), "utf8");
  assert(attribute.includes("FOR UPDATE"), "attribution locks the referrer's codes");
  assert(!attribute.includes("body.referrerUserId"), "the request body is not a trusted referrer");
}

async function main() {
  await testAttribution();
  await testQualification();
  testBoundaries();
  console.log("incentive referral lifecycle ok");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
