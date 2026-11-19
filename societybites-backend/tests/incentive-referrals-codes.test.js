/**
 * Referral code creation and retrieval. No database connection.
 * DATABASE_URL is replaced before the incentive module loads so a developer
 * shell cannot point this file at a remote database.
 */
process.env.DATABASE_URL = "postgresql://postgres:local-test-not-used@127.0.0.1:5432/societybites_incentive_foundation";
process.env.DIRECT_URL = process.env.DATABASE_URL;

const fs = require("fs");
const http = require("http");
const path = require("path");
const express = require("express");

const { assessCampaign } = require("../modules/incentive-engine/campaign/readiness");
const { createMemoryRepository } = require("../modules/incentive-engine/campaign/memoryRepository");
const service = require("../modules/incentive-engine/campaign/service");
const {
  createReferralCode,
  generateReferralCode,
  listReferralCodes,
  previewReferralCode,
  referralLinkBase,
} = require("../modules/incentive-engine/referrals/codes");
const { createReferralsRouter } = require("../modules/incentive-engine/routes/referrals");
const { rateLimit } = require("../middleware/rateLimit");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function flags(overrides) {
  return {
    master: true,
    issuance: false,
    redemption: false,
    referral: true,
    buyerReferral: true,
    sellerReferral: true,
    promotional: false,
    ...overrides,
  };
}

function policy(overrides = {}) {
  return {
    codeExpiresInDays: 30,
    buyer: { maxAccountAgeHours: 72 },
    ...overrides,
  };
}

function readySnapshot(category, extra = {}) {
  return {
    category,
    endsAt: "2026-12-31T00:00:00.000Z",
    audiences: [{ kind: "BUYERS", payload: {} }],
    eligibility: "AUDIENCE_AND_TRIGGER_ONLY",
    rules: null,
    triggers: [{ eventType: "ORDER_QUALIFIED" }],
    rewards: [{ slot: "buyer", rewardType: "FIXED_COUPON", recipientRole: "BUYER", amount: "10.00" }],
    budget: { currency: "INR", amountCap: "100.00" },
    referralPolicy: category === "REPEAT_ORDER" ? null : policy(),
    ...extra,
  };
}

function createCodeRepository() {
  const codes = [];
  const state = {
    flags: flags(),
    campaigns: new Map(),
    versions: new Map(),
    holdInserts: false,
    entered: 0,
    release: null,
    rejectCodeOnce: false,
    inserts: 0,
  };
  return {
    state,
    codes,
    async readFlags() {
      return state.flags;
    },
    async findCampaign(id) {
      return state.campaigns.get(id) || null;
    },
    async findVersion(id) {
      return state.versions.get(id) || null;
    },
    async findCodeByOwner(userId, audience, scopeKey) {
      return codes.find((row) => row.userId === userId && row.audience === audience && row.scopeKey === scopeKey) || null;
    },
    async findCodeByValue(code) {
      return codes.find((row) => row.code === code) || null;
    },
    async listCodes(userId) {
      return codes.filter((row) => row.userId === userId);
    },
    async insertCode(data) {
      state.inserts += 1;
      if (state.holdInserts) {
        state.entered += 1;
        if (state.entered === 1) {
          await new Promise((resolve) => {
            state.release = resolve;
          });
        } else if (state.release) {
          const release = state.release;
          state.release = null;
          release();
        }
      }
      if (state.rejectCodeOnce) {
        state.rejectCodeOnce = false;
        const error = new Error("Unique constraint failed on the fields: (`code`)");
        error.code = "P2002";
        error.meta = { target: ["code"] };
        throw error;
      }
      const owner = codes.find((row) => row.userId === data.userId && row.audience === data.audience && row.scopeKey === data.scopeKey);
      if (owner) {
        const error = new Error("Unique constraint failed on the fields: (`userId`,`audience`,`scopeKey`)");
        error.code = "P2002";
        error.meta = { target: ["userId", "audience", "scopeKey"] };
        throw error;
      }
      const row = {
        id: `code-${state.inserts}`,
        active: true,
        createdAt: new Date().toISOString(),
        ...data,
      };
      codes.push(row);
      return row;
    },
  };
}

function publishCampaign(repository, { id = "camp-1", status = "ACTIVE", category = "BUYER_ACQUISITION", snapshot } = {}) {
  const versionId = "ver-1";
  const stored = snapshot || readySnapshot(category);
  repository.state.versions.set(versionId, {
    id: versionId,
    campaignId: id,
    publishedAt: "2026-11-17T00:00:00.000Z",
    snapshot: stored,
  });
  repository.state.campaigns.set(id, {
    id,
    category,
    status,
    currentVersionId: versionId,
    endsAt: stored.endsAt || null,
  });
  return { id, versionId };
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

function listen(app) {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function request(server, { method, requestPath, body, token }) {
  const address = server.address();
  return new Promise((resolve, reject) => {
    const payload = body ? JSON.stringify(body) : null;
    const req = http.request(
      {
        hostname: "127.0.0.1",
        port: address.port,
        path: requestPath,
        method,
        headers: {
          Accept: "application/json",
          ...(payload ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) } : {}),
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
      },
      (response) => {
        let data = "";
        response.on("data", (chunk) => {
          data += chunk;
        });
        response.on("end", () => {
          let json = null;
          try {
            json = data ? JSON.parse(data) : null;
          } catch (error) {
            json = { raw: data };
          }
          resolve({ status: response.statusCode, json });
        });
      }
    );
    req.on("error", reject);
    if (payload) req.write(payload);
    req.end();
  });
}

async function testReadiness() {
  const repeat = assessCampaign(readySnapshot("REPEAT_ORDER", { referralPolicy: null }));
  assert(repeat.ready === true, "a non-referral campaign does not need referral policy");

  const missing = assessCampaign(readySnapshot("BUYER_ACQUISITION", { referralPolicy: null }));
  assert(missing.ready === false, "buyer acquisition without policy is not ready");
  assert(missing.failures.some((failure) => failure.code === "REFERRAL_POLICY_INVALID"), "missing policy is named");

  const noWindow = assessCampaign(readySnapshot("REFERRAL", { referralPolicy: { codeExpiresInDays: 10 } }));
  assert(noWindow.failures.some((failure) => failure.code === "ATTRIBUTION_WINDOW_REQUIRED"), "buyer window is required");

  const seller = assessCampaign(readySnapshot("SELLER_ACQUISITION", {
    referralPolicy: { codeExpiresInDays: 10 },
    audiences: [{ kind: "SELLERS", payload: {} }],
  }));
  assert(seller.ready === true, "seller acquisition can omit the buyer account window");
  assert(!seller.failures.some((failure) => failure.code === "ATTRIBUTION_WINDOW_REQUIRED"), "seller policy does not demand a buyer window");

  const immortal = assessCampaign(readySnapshot("SELLER_ACQUISITION", {
    endsAt: null,
    referralPolicy: { codeExpiresInDays: null },
    audiences: [{ kind: "SELLERS", payload: {} }],
  }));
  assert(immortal.failures.some((failure) => failure.code === "CODE_EXPIRY_REQUIRED"), "a code with no lifetime and no campaign end is rejected");

  const repo = createMemoryRepository();
  const created = await service.createCampaign(repo, {
    actorId: "admin-1",
    body: { name: "Buyer welcome", category: "BUYER_ACQUISITION", endsAt: "2026-12-31T00:00:00.000Z" },
  });
  await expectError(
    () => service.setReferralPolicy(repo, { campaignId: created.id, actorId: "admin-1", body: { referralPolicy: { codeExpiresInDays: 10 } } }),
    400,
    "ATTRIBUTION_WINDOW_REQUIRED"
  );
  const saved = await service.setReferralPolicy(repo, {
    campaignId: created.id,
    actorId: "admin-1",
    body: { referralPolicy: policy({ codeExpiresInDays: 14 }) },
  });
  assert(saved.version.snapshot.referralPolicy.codeExpiresInDays === 14, "policy is stored on the snapshot");
  const renamed = await service.updateCampaign(repo, {
    campaignId: created.id,
    actorId: "admin-1",
    body: { name: "Buyer welcome revised", endsAt: "2027-01-31T00:00:00.000Z" },
  });
  assert(renamed.version.snapshot.referralPolicy.codeExpiresInDays === 14, "editing the campaign keeps the stored policy");
  const other = await service.createCampaign(repo, { actorId: "admin-1", body: { name: "Repeat", category: "REPEAT_ORDER" } });
  await expectError(
    () => service.setReferralPolicy(repo, { campaignId: other.id, actorId: "admin-1", body: { referralPolicy: policy() } }),
    400,
    "REFERRAL_POLICY_NOT_APPLICABLE"
  );
}

async function testIssuance() {
  const repository = createCodeRepository();
  publishCampaign(repository);
  const user = { id: "buyer-1", role: "buyer" };
  const now = new Date("2026-11-17T00:00:00.000Z");
  const created = await createReferralCode(repository, {
    user,
    now,
    body: { audience: "BUYER", campaignId: "camp-1", userId: "someone-else" },
  });
  assert(created.created === true, "first create is new");
  assert(created.code.campaignVersionId === "ver-1", "code is pinned to the published version");
  assert(repository.codes[0].userId === "buyer-1", "caller-supplied user id is ignored");
  assert(!Object.prototype.hasOwnProperty.call(created.code, "userId"), "response does not echo a user id");
  const expectedExpiry = new Date("2026-12-17T00:00:00.000Z").toISOString();
  assert(created.code.expiresAt === expectedExpiry, "lifetime is earlier than the campaign end");
  assert(created.code.url === null, "missing link base returns a null url");
  assert(created.code.path === `/r/${created.code.code}`, "path contains only the code");

  repository.state.versions.get("ver-1").snapshot.endsAt = "2026-11-20T00:00:00.000Z";
  repository.state.versions.get("ver-1").id = "ver-2";
  repository.state.campaigns.get("camp-1").currentVersionId = "ver-9";
  repository.state.campaigns.get("camp-1").endsAt = "2027-06-01T00:00:00.000Z";
  repository.state.campaigns.get("camp-1").status = "PAUSED";
  const again = await createReferralCode(repository, {
    user,
    now: new Date("2026-11-18T00:00:00.000Z"),
    body: { audience: "BUYER", campaignId: "camp-1" },
  });
  assert(again.created === false, "second create returns the existing code");
  assert(again.code.code === created.code.code, "the code value does not change");
  assert(again.code.expiresAt === expectedExpiry, "expiry is not recalculated after the campaign changes");
  assert(again.code.campaignVersionId === "ver-1", "the pinned version does not move");
  assert(repository.state.inserts === 1, "idempotent create does not insert again");

  const listed = await listReferralCodes(repository, { user });
  assert(listed.codes.length === 1, "owner list returns only that user's code");
  assert(listed.codes[0].code === created.code.code, "owner list returns the issued code");

  repository.state.rejectCodeOnce = true;
  const sellerRepo = createCodeRepository();
  publishCampaign(sellerRepo, { category: "SELLER_ACQUISITION", snapshot: readySnapshot("SELLER_ACQUISITION", {
    referralPolicy: { codeExpiresInDays: 5 },
    audiences: [{ kind: "SELLERS", payload: {} }],
  }) });
  sellerRepo.state.rejectCodeOnce = true;
  const sequence = ["AAAAAAAAAAAAAAA1", "BBBBBBBBBBBBBBB2"];
  const issued = await createReferralCode(sellerRepo, {
    user: { id: "seller-1", role: "seller" },
    now,
    generateCode: () => sequence.shift(),
    body: { audience: "SELLER", campaignId: "camp-1" },
  });
  assert(issued.code.code === "BBBBBBBBBBBBBBB2", "a code collision retries with a new code");
  assert(sellerRepo.codes.length === 1, "a collided code is not stored");
}

async function testConcurrency() {
  const repository = createCodeRepository();
  publishCampaign(repository);
  repository.state.holdInserts = true;
  const now = new Date("2026-11-17T00:00:00.000Z");
  const body = { audience: "BUYER", campaignId: "camp-1" };
  const user = { id: "buyer-1", role: "buyer" };
  const pair = Promise.all([
    createReferralCode(repository, { user, now, body }),
    createReferralCode(repository, { user, now, body }),
  ]);
  const results = await Promise.race([
    pair,
    new Promise((_, reject) => setTimeout(() => reject(new Error("concurrent create timed out")), 2000)),
  ]);
  assert(repository.codes.length === 1, "concurrent creates leave one row");
  assert(results[0].code.code === results[1].code.code, "both creates observe the same code");
  assert(results.filter((result) => result.created).length === 1, "one create wins and the other reuses it");
}

async function testGuards() {
  const now = new Date("2026-11-17T00:00:00.000Z");
  const buyer = { id: "buyer-1", role: "buyer" };
  const seller = { id: "seller-1", role: "seller" };
  const admin = { id: "admin-1", role: "super_admin" };

  async function issue(repository, user, audience) {
    return createReferralCode(repository, { user, now, body: { audience, campaignId: "camp-1" } });
  }

  const off = createCodeRepository();
  publishCampaign(off);
  off.state.flags = flags({ master: false, referral: false, buyerReferral: false, sellerReferral: false });
  await expectError(() => issue(off, buyer, "BUYER"), 403, "REFERRAL_DISABLED");
  await expectError(() => listReferralCodes(off, { user: buyer }), 403, "REFERRAL_DISABLED");
  assert(off.state.inserts === 0, "flags off do not write a code");

  const buyerOnly = createCodeRepository();
  publishCampaign(buyerOnly, { category: "REFERRAL", snapshot: readySnapshot("REFERRAL") });
  buyerOnly.state.flags = flags({ sellerReferral: false });
  await expectError(() => issue(buyerOnly, seller, "ANY"), 403, "REFERRAL_DISABLED");
  await expectError(() => issue(buyerOnly, seller, "SELLER"), 403, "REFERRAL_DISABLED");
  assert(buyerOnly.state.inserts === 0, "ANY with a referral flag off does not write");
  const buyerCode = await issue(buyerOnly, buyer, "BUYER");
  assert(buyerCode.created === true, "the enabled buyer audience can still be issued");

  const sellerOnly = createCodeRepository();
  publishCampaign(sellerOnly, { category: "SELLER_ACQUISITION", snapshot: readySnapshot("SELLER_ACQUISITION", {
    referralPolicy: { codeExpiresInDays: 9 },
    audiences: [{ kind: "SELLERS", payload: {} }],
  }) });
  sellerOnly.state.flags = flags({ buyerReferral: false });
  await expectError(() => issue(sellerOnly, seller, "ANY"), 403, "REFERRAL_DISABLED");
  assert(sellerOnly.state.inserts === 0, "ANY with the buyer flag off does not write");

  const roles = createCodeRepository();
  publishCampaign(roles, { category: "REFERRAL", snapshot: readySnapshot("REFERRAL") });
  await expectError(() => issue(roles, buyer, "SELLER"), 403, "SELLER_REQUIRED");
  await expectError(() => issue(roles, buyer, "ANY"), 403, "SELLER_REQUIRED");
  assert(roles.state.inserts === 0, "a buyer cannot create a seller or any code");
  assert((await issue(roles, seller, "SELLER")).created === true, "a seller can create a seller code");
  assert((await issue(roles, admin, "ANY")).created === true, "a super admin can create an any code");
  assert((await issue(roles, buyer, "BUYER")).created === true, "a buyer can create a buyer code");

  const statuses = ["DRAFT", "PAUSED", "EXPIRED", "TERMINATED", "COMPLETED"];
  const codes = {
    DRAFT: "CAMPAIGN_NOT_ACTIVE",
    PAUSED: "CAMPAIGN_PAUSED",
    EXPIRED: "CAMPAIGN_EXPIRED",
    TERMINATED: "CAMPAIGN_TERMINATED",
    COMPLETED: "CAMPAIGN_NOT_ACTIVE",
  };
  for (const status of statuses) {
    const repository = createCodeRepository();
    publishCampaign(repository, { status });
    await expectError(() => issue(repository, buyer, "BUYER"), 409, codes[status]);
    assert(repository.state.inserts === 0, `${status} does not write a code`);
  }

  const unpublished = createCodeRepository();
  publishCampaign(unpublished);
  unpublished.state.versions.get("ver-1").publishedAt = null;
  await expectError(() => issue(unpublished, buyer, "BUYER"), 409, "CAMPAIGN_VERSION_UNPUBLISHED");

  const invalidPolicy = createCodeRepository();
  publishCampaign(invalidPolicy, { snapshot: readySnapshot("BUYER_ACQUISITION", { referralPolicy: null }) });
  await expectError(() => issue(invalidPolicy, buyer, "BUYER"), 400, "REFERRAL_POLICY_INVALID");

  const missingWindow = createCodeRepository();
  publishCampaign(missingWindow, { snapshot: readySnapshot("BUYER_ACQUISITION", { referralPolicy: { codeExpiresInDays: 4 } }) });
  await expectError(() => issue(missingWindow, buyer, "BUYER"), 400, "ATTRIBUTION_WINDOW_REQUIRED");

  const scheduled = createCodeRepository();
  publishCampaign(scheduled, { status: "SCHEDULED" });
  assert((await issue(scheduled, buyer, "BUYER")).created === true, "a scheduled campaign can issue a code");

  const inactive = createCodeRepository();
  publishCampaign(inactive);
  const issued = await issue(inactive, buyer, "BUYER");
  inactive.codes[0].active = false;
  await expectError(() => issue(inactive, buyer, "BUYER"), 409, "CODE_INACTIVE");
  assert(inactive.codes.length === 1, "an inactive code is not replaced");
  assert(issued.code.code !== undefined, "the first response was a usable code");
  assert(inactive.codes[0].active === false, "the stored code stays inactive");
}

async function testPreviewAndLinks() {
  assert(referralLinkBase({ REFERRAL_LINK_BASE_URL: undefined }) === null, "missing base is null");
  assert(referralLinkBase({ REFERRAL_LINK_BASE_URL: "" }) === null, "empty base is null");
  assert(referralLinkBase({ REFERRAL_LINK_BASE_URL: "http://example.com" }) === null, "http base is rejected");
  assert(referralLinkBase({ REFERRAL_LINK_BASE_URL: "https://example.com/r" }) === null, "a path is rejected");
  assert(referralLinkBase({ REFERRAL_LINK_BASE_URL: "https://user:pass@example.com" }) === null, "credentials are rejected");
  assert(referralLinkBase({ REFERRAL_LINK_BASE_URL: "https://example.com?code=1" }) === null, "a query is rejected");
  assert(referralLinkBase({ REFERRAL_LINK_BASE_URL: "not a url" }) === null, "an unparsable base is rejected");
  assert(referralLinkBase({ REFERRAL_LINK_BASE_URL: " https://example.com" }) === null, "surrounding space is rejected");
  assert(referralLinkBase({ REFERRAL_LINK_BASE_URL: "https://example.com" }) === "https://example.com", "an https origin is accepted");

  const generated = generateReferralCode();
  assert(/^[0-9A-HJKMNP-TV-Z]{16}$/.test(generated), "generated codes match the public alphabet");
  assert(!generated.includes("I") && !generated.includes("L") && !generated.includes("O") && !generated.includes("U"), "ambiguous characters are omitted");

  const repository = createCodeRepository();
  publishCampaign(repository);
  const created = await createReferralCode(repository, {
    user: { id: "buyer-1", role: "buyer" },
    now: new Date("2026-11-17T00:00:00.000Z"),
    env: { REFERRAL_LINK_BASE_URL: "https://links.example" },
    body: { audience: "BUYER", campaignId: "camp-1" },
  });
  assert(created.code.url === `https://links.example/r/${created.code.code}`, "url uses the configured origin and the code");
  repository.codes[0].userId = "buyer-1";
  repository.codes[0].phone = "9999999999";
  const preview = await previewReferralCode(repository, { code: created.code.code, now: new Date("2026-11-18T00:00:00.000Z") });
  assert(JSON.stringify(Object.keys(preview).sort()) === JSON.stringify(["audience", "expiresAt", "valid"]), "preview has only three fields");
  assert(preview.valid === true, "an active code previews as valid");
  assert(preview.audience === "BUYER", "preview returns the audience");
  assert(!JSON.stringify(preview).includes("buyer-1"), "preview does not reveal the owner");
  assert(!JSON.stringify(preview).includes("9999999999"), "preview does not reveal a phone");

  const hidden = await previewReferralCode(repository, { code: "not-a-real-code" });
  assert(hidden.valid === false && hidden.audience === null && hidden.expiresAt === null, "an unknown code reveals nothing");
  repository.codes[0].active = false;
  const inactive = await previewReferralCode(repository, { code: created.code.code });
  assert(inactive.valid === false && inactive.audience === null, "an inactive code reveals nothing");
  repository.codes[0].active = true;
  const expired = await previewReferralCode(repository, { code: created.code.code, now: new Date("2027-01-01T00:00:00.000Z") });
  assert(expired.valid === false && expired.expiresAt === null, "an expired code reveals nothing");

  repository.state.flags = flags({ referral: false });
  const switchedOff = await previewReferralCode(repository, { code: created.code.code, now: new Date("2026-11-18T00:00:00.000Z") });
  assert(switchedOff.valid === false && switchedOff.audience === null, "preview fails closed while referral is off");
}

async function testHttp() {
  const repository = createCodeRepository();
  publishCampaign(repository);
  const users = {
    "buyer-1": { id: "buyer-1", role: "buyer" },
  };
  const app = express();
  app.use(express.json());
  app.use("/incentive", createReferralsRouter({
    repository,
    previewLimit: (req, res, next) => next(),
    requireUser(req, res, next) {
      const header = req.header("Authorization") || "";
      const token = header.startsWith("Bearer ") ? header.slice(7) : "";
      if (!users[token]) return res.status(401).json({ error: "Missing or invalid Authorization header" });
      req.user = users[token];
      next();
    },
  }));
  const server = await listen(app);
  try {
    const anonymous = await request(server, { method: "POST", requestPath: "/incentive/referral-codes", body: { audience: "BUYER", campaignId: "camp-1" } });
    assert(anonymous.status === 401, "create requires a JWT");
    const created = await request(server, {
      method: "POST",
      requestPath: "/incentive/referral-codes",
      token: "buyer-1",
      body: { audience: "BUYER", campaignId: "camp-1", userId: "other-user" },
    });
    assert(created.status === 201, "create returns 201");
    assert(repository.codes[0].userId === "buyer-1", "the route uses the authenticated user");
    const repeat = await request(server, {
      method: "POST",
      requestPath: "/incentive/referral-codes",
      token: "buyer-1",
      body: { audience: "BUYER", campaignId: "camp-1" },
    });
    assert(repeat.status === 200, "repeat create returns 200");
    assert(repeat.json.code === created.json.code, "repeat create returns the same code");
    const preview = await request(server, {
      method: "GET",
      requestPath: `/incentive/referral-codes/preview?code=${created.json.code}`,
    });
    assert(preview.status === 200, "preview is public");
    assert(Object.keys(preview.json).sort().join() === "audience,expiresAt,valid", "public preview stays limited to three fields");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }

  const limited = express();
  limited.use(createReferralsRouter({
    repository,
    previewLimit: rateLimit({ windowMs: 60000, max: 2 }),
    requireUser(req, res, next) {
      next();
    },
  }));
  const limitedServer = await listen(limited);
  try {
    const first = await request(limitedServer, { method: "GET", requestPath: "/referral-codes/preview?code=UNKNOWNCODE00000" });
    const second = await request(limitedServer, { method: "GET", requestPath: "/referral-codes/preview?code=UNKNOWNCODE00000" });
    const third = await request(limitedServer, { method: "GET", requestPath: "/referral-codes/preview?code=UNKNOWNCODE00000" });
    assert(first.status === 200 && second.status === 200, "preview allows the configured number of requests");
    assert(third.status === 429, "preview rate limit returns 429");
  } finally {
    await new Promise((resolve) => limitedServer.close(resolve));
  }
}

function testSourceBoundaries() {
  const root = path.join(__dirname, "..", "modules", "incentive-engine");
  const source = fs.readFileSync(path.join(root, "referrals", "codes.js"), "utf8");
  assert(!source.includes("incentiveReferral."), "code creation does not write referral attribution");
  assert(!source.includes("incentiveReward"), "code creation does not write rewards");
  assert(!source.includes("incentiveLedger"), "code creation does not write the ledger");
  assert(!source.includes("finish("), "code creation does not change event finish");
}

async function main() {
  await testReadiness();
  await testIssuance();
  await testConcurrency();
  await testGuards();
  await testPreviewAndLinks();
  await testHttp();
  testSourceBoundaries();
  console.log("incentive referral codes ok");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
