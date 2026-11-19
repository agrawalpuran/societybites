const fs = require("fs");
const http = require("http");
const path = require("path");
const express = require("express");

const { ALL_OFF, readFlags } = require("../modules/incentive-engine/configuration/flags");
const { STATUSES } = require("../modules/incentive-engine/rules/catalog");
const { evaluateRules } = require("../modules/incentive-engine/rules/evaluate");
const { createMemoryRepository } = require("../modules/incentive-engine/campaign/memoryRepository");
const { createPrismaRepository } = require("../modules/incentive-engine/campaign/prismaRepository");
const service = require("../modules/incentive-engine/campaign/service");
const { createAdminRouter } = require("../modules/incentive-engine/routes/adminCampaigns");
const { requireAdmin, requireSuperAdmin } = require("../middleware/requireAdmin");

const actorId = "admin-1";
const enabledForTest = Object.freeze({
  master: true,
  issuance: false,
  redemption: false,
  referral: false,
  buyerReferral: false,
  sellerReferral: false,
  promotional: false,
});

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function expectStatus(work, status, text) {
  try {
    await work();
  } catch (error) {
    assert(error.statusCode === status, `expected HTTP ${status}, got ${error.statusCode || "none"}: ${error.message}`);
    if (text) assert(String(error.message).includes(text), error.message);
    return error;
  }
  throw new Error(`expected HTTP ${status}`);
}

function leaf(field, operator, value) {
  const node = { field, operator };
  if (operator !== "EXISTS") node.value = value;
  return node;
}

async function createDraft(repo, body) {
  return service.createCampaign(repo, {
    actorId,
    body: {
      name: "Repeat lunch",
      category: "REPEAT_ORDER",
      description: "Configuration only",
      priority: 5,
      startsAt: "2026-01-01T00:00:00.000Z",
      endsAt: "2026-12-31T00:00:00.000Z",
      ...body,
    },
  });
}

async function configure(repo, campaignId, extras = {}) {
  await service.setAudiences(repo, {
    campaignId,
    actorId,
    body: { audiences: extras.audiences || [{ kind: "BUYERS" }, { kind: "SELLERS" }] },
  });
  const withTriggers = await service.setTriggers(repo, {
    campaignId,
    actorId,
    body: { triggers: extras.triggers || ["ORDER_QUALIFIED"] },
  });
  const eligibility = extras.eligibility || "RULES";
  if (extras.skipRules !== true) {
    await service.setRules(repo, {
      campaignId,
      actorId,
      body: eligibility === "AUDIENCE_AND_TRIGGER_ONLY"
        ? { eligibility }
        : {
            eligibility,
            rules: extras.rules || {
              combinator: "AND",
              conditions: [leaf("order.total", "GREATER_THAN_OR_EQUAL", 100)],
            },
          },
    });
  }
  if (extras.skipRewards !== true) {
    await service.setRewards(repo, {
      campaignId,
      actorId,
      body: {
        rewards: extras.rewards || [
          { slot: "buyer", recipientRole: "BUYER", rewardType: "FIXED_COUPON", amount: 20 },
        ],
      },
    });
  }
  if (extras.skipBudget === true) {
    return { triggers: withTriggers, saved: await service.getCampaign(repo, campaignId) };
  }
  return {
    triggers: withTriggers,
    saved: await service.setBudget(repo, {
      campaignId,
      actorId,
      body: extras.budget || { amountCap: 1000, maxRewardCount: 10, maxRewardAmount: 50 },
    }),
  };
}

function testUser(req, res, next) {
  const role = req.headers["x-role"];
  if (!role) return res.status(401).json({ error: "Missing or invalid Authorization header" });
  req.user = { id: actorId, role, consoleAdmin: req.headers["x-console"] === "1" };
  next();
}

function jsonRequest(server, { method, requestPath, role, consoleAdmin, body }) {
  const payload = body == null ? null : JSON.stringify(body);
  const headers = { Accept: "application/json" };
  if (role) headers["x-role"] = role;
  if (consoleAdmin) headers["x-console"] = "1";
  if (payload) {
    headers["Content-Type"] = "application/json";
    headers["Content-Length"] = Buffer.byteLength(payload);
  }
  const address = server.address();
  return new Promise((resolve, reject) => {
    const request = http.request(
      {
        hostname: "127.0.0.1",
        port: address.port,
        path: requestPath,
        method,
        headers,
      },
      (response) => {
        let data = "";
        response.on("data", (chunk) => (data += chunk));
        response.on("end", () => {
          let json = null;
          try {
            json = data ? JSON.parse(data) : null;
          } catch (_) {
            json = null;
          }
          resolve({ status: response.statusCode, json });
        });
      }
    );
    request.on("error", reject);
    if (payload) request.write(payload);
    request.end();
  });
}

async function testRules() {
  const operators = [
    ["EQUALS", "user.role", "buyer", "buyer", true],
    ["NOT_EQUALS", "user.role", "seller", "buyer", true],
    ["IN", "order.status", ["completed"], "completed", true],
    ["NOT_IN", "order.status", ["cancelled"], "completed", true],
    ["EXISTS", "user.societyId", undefined, "soc-1", true],
    ["GREATER_THAN", "order.total", 10, 11, true],
    ["LESS_THAN", "order.total", 10, 9, true],
    ["GREATER_THAN_OR_EQUAL", "order.total", 10, 10, true],
    ["LESS_THAN_OR_EQUAL", "order.total", 10, 10, true],
    ["BETWEEN", "review.rating", [1, 5], 4, true],
  ];
  for (const [operator, field, expected, actual, passed] of operators) {
    const result = evaluateRules(leaf(field, operator, expected), { [field]: actual });
    assert(result.passed === passed, `${operator} should pass`);
    assert(result.results.some((row) => row.field === field && row.passed === passed), `${operator} explanation`);
  }

  const failed = evaluateRules(leaf("user.role", "EQUALS", "buyer"), { "user.role": "seller" });
  assert(failed.passed === false, "failed comparison is explained");
  assert(failed.results[0].actual === "seller", "failed comparison shows the actual value");

  const mixed = evaluateRules(
    {
      combinator: "OR",
      conditions: [
        {
          combinator: "AND",
          conditions: [leaf("order.total", "GREATER_THAN", 100), leaf("user.role", "EQUALS", "buyer")],
        },
        leaf("order.isFirstCompleted", "EQUALS", true),
      ],
    },
    { "order.total": 10, "user.role": "seller", "order.isFirstCompleted": true }
  );
  assert(mixed.passed === true, "OR group passes when one branch passes");
  const andFail = evaluateRules(
    { combinator: "AND", conditions: [leaf("order.total", "GREATER_THAN", 100), leaf("user.role", "EQUALS", "buyer")] },
    { "order.total": 10, "user.role": "buyer" }
  );
  assert(andFail.passed === false, "AND group fails when one condition fails");
  assert(evaluateRules(null, {}).passed === false, "a missing rule tree is not eligibility");

  const repo = createMemoryRepository();
  const created = await createDraft(repo);
  let depth = leaf("order.itemCount", "EQUALS", 1);
  for (let i = 0; i < 3; i += 1) depth = { combinator: "AND", conditions: [depth] };
  await service.setRules(repo, { campaignId: created.id, actorId, body: { eligibility: "RULES", rules: depth } });
  let tooDeep = leaf("order.itemCount", "EQUALS", 1);
  for (let i = 0; i < 4; i += 1) tooDeep = { combinator: "AND", conditions: [tooDeep] };
  await expectStatus(
    () => service.setRules(repo, { campaignId: created.id, actorId, body: { eligibility: "RULES", rules: tooDeep } }),
    400,
    "cannot exceed 4"
  );

  const thirty = Array.from({ length: 30 }, () => leaf("order.itemCount", "EQUALS", 1));
  await service.setRules(repo, {
    campaignId: created.id,
    actorId,
    body: { eligibility: "RULES", rules: { combinator: "OR", conditions: thirty } },
  });
  await expectStatus(
    () =>
      service.setRules(repo, {
        campaignId: created.id,
        actorId,
        body: { eligibility: "RULES", rules: { combinator: "OR", conditions: [...thirty, leaf("order.itemCount", "EQUALS", 2)] } },
      }),
    400,
    "30"
  );
  await expectStatus(
    () => service.setRules(repo, { campaignId: created.id, actorId, body: { eligibility: "RULES", rules: leaf("order.secret", "EQUALS", "x") } }),
    400,
    "Unsupported rule field"
  );
  await expectStatus(
    () => service.setRules(repo, { campaignId: created.id, actorId, body: { eligibility: "RULES", rules: leaf("user.role", "GREATER_THAN", 1) } }),
    400,
    "not allowed"
  );
  await expectStatus(
    () => service.setRules(repo, { campaignId: created.id, actorId, body: { eligibility: "RULES", rules: leaf("order.total", "EQUALS", "10") } }),
    400,
    "number"
  );
  await expectStatus(
    () => service.setRules(repo, { campaignId: created.id, actorId, body: { eligibility: "RULES", rules: "user.role == 'buyer'" } }),
    400,
    "object"
  );
}

async function testCampaignLifecycle() {
  assert(!STATUSES.includes("READY_FOR_REVIEW"), "review state is not part of the approved lifecycle");
  const repo = createMemoryRepository();
  const writesAtStart = repo.writes();
  await expectStatus(
    () => createDraft(repo, { status: "ACTIVE" }),
    400,
    "lifecycle action"
  );
  assert(repo.writes() === writesAtStart, "rejected create does not write");

  const created = await createDraft(repo);
  assert(created.status === "DRAFT", "create is always a draft");
  assert(created.version.versionNumber === 1, "first version");
  assert(created.version.publishedAt == null, "draft version is unpublished");
  const renamed = await service.updateCampaign(repo, {
    campaignId: created.id,
    actorId,
    body: { name: "Repeat lunch revised" },
  });
  assert(renamed.name === "Repeat lunch revised", "draft name edits in place");
  assert((await service.listVersions(repo, created.id)).length === 1, "draft edit does not fork");

  await expectStatus(
    () => service.setAudiences(repo, { campaignId: created.id, actorId, body: { audiences: [{ kind: "APPROVED_SELLERS" }] } }),
    400,
    "Unsupported audience"
  );
  const configured = await configure(repo, created.id);
  assert(configured.triggers.version.snapshot.triggers[0].processor === "NOT_IMPLEMENTED", "trigger is configuration only");
  assert(configured.saved.version.processor === "NOT_IMPLEMENTED", "campaign processor is not implemented");
  assert(configured.saved.version.snapshot.budget.maxRewardCount === 10, "reward count limit is stored");
  assert(configured.saved.version.snapshot.budget.issuedAmount === "0.00", "budget is not consumed");

  const buyerOnly = createMemoryRepository();
  const buyerCampaign = await createDraft(buyerOnly, { category: "BUYER_ACQUISITION" });
  await expectStatus(
    () => service.changeStatus(buyerOnly, { campaignId: buyerCampaign.id, actorId, to: "ACTIVATE", flags: enabledForTest }),
    403,
    "Referral campaigns are off"
  );
  const festive = createMemoryRepository();
  const festiveCampaign = await createDraft(festive, { category: "FESTIVE" });
  await expectStatus(
    () => service.changeStatus(festive, { campaignId: festiveCampaign.id, actorId, to: "ACTIVATE", flags: enabledForTest }),
    403,
    "Promotional campaigns are off"
  );

  const beforeBlocked = repo.writes();
  const blocked = await expectStatus(
    () => service.changeStatus(repo, { campaignId: created.id, actorId, to: "ACTIVATE", flags: { ...ALL_OFF } }),
    403,
    "engine is off"
  );
  assert(blocked.code === "ENGINE_DISABLED", "blocked activation names the master switch");
  assert(repo.writes() === beforeBlocked, "blocked activation does not write");
  assert((await service.getCampaign(repo, created.id)).status === "DRAFT", "blocked activation stays draft");

  const points = createMemoryRepository();
  const pointsCampaign = await createDraft(points);
  await service.setRewards(points, {
    campaignId: pointsCampaign.id,
    actorId,
    body: { rewards: [{ slot: "score", recipientRole: "BUYER", rewardType: "POINTS", amount: 500 }] },
  });
  await service.setBudget(points, { campaignId: pointsCampaign.id, actorId, body: { amountCap: 10 } });
  await expectStatus(
    () =>
      service.setRewards(repo, {
        campaignId: created.id,
        actorId,
        body: { rewards: [{ slot: "buyer", recipientRole: "BUYER", rewardType: "FIXED_COUPON", amount: 80 }] },
      }),
    400,
    "maximum reward amount"
  );
  await expectStatus(
    () =>
      service.setRewards(repo, {
        campaignId: created.id,
        actorId,
        body: { rewards: [{ slot: "percent", recipientRole: "BUYER", rewardType: "PERCENTAGE_COUPON", amount: 10 }] },
      }),
    400,
    "Maximum discount"
  );
  await expectStatus(
    () => service.setBudget(repo, { campaignId: created.id, actorId, body: { amountCap: -1 } }),
    400,
    "negative"
  );
  await expectStatus(
    () => service.setBudget(repo, { campaignId: created.id, actorId, body: { amountCap: 10, issuedAmount: 5 } }),
    400,
    "cannot be set"
  );
  await expectStatus(() => createDraft(repo, { endsAt: "2025-01-01T00:00:00.000Z" }), 400, "after the start");

  const activated = await service.changeStatus(repo, {
    campaignId: created.id,
    actorId,
    to: "ACTIVATE",
    flags: enabledForTest,
    now: new Date("2026-06-01T00:00:00.000Z"),
  });
  assert(activated.status === "ACTIVE", "explicit activation can be exercised with an in-memory flag object");
  assert(activated.version.publishedAt != null, "activation freezes the version");
  const frozenId = activated.version.id;
  const frozenName = activated.version.snapshot.name;
  const edited = await service.updateCampaign(repo, { campaignId: created.id, actorId, body: { name: "Second version" } });
  assert(edited.status === "DRAFT", "editing a published campaign returns it to draft");
  assert(edited.version.versionNumber === 2, "edit forks a new version");
  const history = await service.getVersion(repo, created.id, frozenId);
  assert(history.snapshot.name === frozenName, "published snapshot stays unchanged");
  assert(history.publishedAt != null, "historical version stays available");
  await expectStatus(() => repo.saveVersion({ ...history, id: frozenId, snapshot: { name: "tampered" } }), 409);

  const republished = await configure(repo, created.id);
  assert(republished.saved.version.id !== frozenId, "new configuration is on the new version");
  const activeAgain = await service.changeStatus(repo, {
    campaignId: created.id,
    actorId,
    to: "ACTIVATE",
    flags: enabledForTest,
    now: new Date("2026-06-02T00:00:00.000Z"),
  });
  assert(activeAgain.version.id !== frozenId, "second activation publishes the new version");
  const paused = await service.changeStatus(repo, { campaignId: created.id, actorId, to: "PAUSED" });
  assert(paused.status === "PAUSED", "pause does not require the master switch");
  await expectStatus(
    () => service.changeStatus(repo, { campaignId: created.id, actorId, to: "ACTIVATE", flags: { ...ALL_OFF } }),
    403
  );
  assert((await service.getCampaign(repo, created.id)).status === "PAUSED", "resume stays blocked while the engine is off");

  const scheduledRepo = createMemoryRepository();
  const scheduledDraft = await createDraft(scheduledRepo, { startsAt: "2026-08-01T00:00:00.000Z" });
  await configure(scheduledRepo, scheduledDraft.id);
  const scheduled = await service.changeStatus(scheduledRepo, {
    campaignId: scheduledDraft.id,
    actorId,
    to: "ACTIVATE",
    flags: enabledForTest,
    now: new Date("2026-07-01T00:00:00.000Z"),
  });
  assert(scheduled.status === "SCHEDULED", "future start schedules instead of going active");

  const ended = await service.changeStatus(repo, {
    campaignId: created.id,
    actorId,
    to: "EXPIRED",
    now: new Date("2027-01-01T00:00:00.000Z"),
  });
  assert(ended.status === "EXPIRED", "explicit expiry keeps the record");
  assert((await service.listVersions(repo, created.id)).length >= 2, "expiry does not delete versions");
  await expectStatus(
    () => service.updateCampaign(repo, { campaignId: created.id, actorId, body: { name: "too late" } }),
    409
  );

  const terminal = createMemoryRepository();
  const toEnd = await createDraft(terminal);
  const terminated = await service.changeStatus(terminal, { campaignId: toEnd.id, actorId, to: "TERMINATED" });
  assert(terminated.status === "TERMINATED", "termination is explicit");
  assert((await service.listVersions(terminal, toEnd.id)).length === 1, "termination keeps history");
  assert(!terminal.deleteCampaign, "repository has no campaign delete");
  assert(terminal.issued().rewards.length === 0, "no rewards");
  assert(terminal.issued().ledger.length === 0, "no ledger");
  assert(terminal.issued().coupons.length === 0, "no coupons");
  assert(terminal.issued().referrals.length === 0, "no referrals");
  assert(terminal.issued().events.length === 0, "no events");
}

async function testSimulation() {
  const repo = createMemoryRepository();
  const created = await createDraft(repo);
  await configure(repo, created.id, {
    rules: {
      combinator: "AND",
      conditions: [leaf("order.total", "GREATER_THAN_OR_EQUAL", 100), leaf("user.role", "EQUALS", "buyer")],
    },
  });
  const before = JSON.stringify(await service.getCampaign(repo, created.id));
  const writes = repo.writes();
  const sample = {
    "user.role": "buyer",
    "event.type": "ORDER_QUALIFIED",
    "order.total": 80,
  };
  const first = await service.simulate(repo, { campaignId: created.id, attributes: sample });
  const second = await service.simulate(repo, { campaignId: created.id, attributes: { ...sample, "order.total": 120 } });
  assert(repo.writes() === writes, "simulation performs no writes");
  assert(JSON.stringify(await service.getCampaign(repo, created.id)) === before, "simulation does not change the campaign");
  assert(first.eligible === false, "failed rule is not eligible");
  assert(first.rules.results.some((row) => row.field === "order.total" && row.passed === false), "simulation explains the failed condition");
  assert(first.audience.passed === true, "buyer audience matches");
  assert(first.trigger.passed === true, "configured trigger matches the sample");
  assert(first.trigger.processor === "NOT_IMPLEMENTED", "simulation does not claim the trigger is processed");
  assert(first.rewards[0].issued === false, "simulation does not issue the reward");
  assert(first.budget.consumed === false, "simulation does not consume budget");
  assert(first.budget.issuedAmount === "0.00", "issued amount stays zero");
  assert(first.writes === 0, "simulation reports no writes");
  assert(second.eligible === true, "passing sample is eligible");
  assert(repo.issued().rewards.length === 0, "simulation creates no reward rows");
  assert(repo.issued().ledger.length === 0, "simulation creates no ledger rows");
  assert(repo.issued().coupons.length === 0, "simulation creates no coupons");

  const seller = await service.simulate(repo, {
    campaignId: created.id,
    attributes: { "user.role": "seller", "event.type": "ORDER_QUALIFIED", "order.total": 120 },
  });
  assert(seller.audience.checks.find((row) => row.kind === "SELLERS").passed === true, "seller audience stays distinct");
  assert(seller.audience.checks.find((row) => row.kind === "BUYERS").passed === false, "buyer audience does not match a seller");
}

async function testPrismaRepositoryGuard() {
  const missing = createPrismaRepository({});
  await expectStatus(() => missing.listCampaigns(), 503, "not available");

  const deletes = [];
  const budgets = [];
  const versions = new Map();
  const tx = {
    incentiveCampaignVersion: {
      async create({ data }) {
        const row = { id: "ver-1", publishedAt: null, publishedBy: null, ...data };
        versions.set(row.id, row);
        return row;
      },
      async findUnique({ where }) {
        return versions.get(where.id) || null;
      },
      async update({ where, data }) {
        Object.assign(versions.get(where.id), data);
        return versions.get(where.id);
      },
    },
    incentiveAudience: { async deleteMany(args) { deletes.push(args); }, async createMany() {} },
    incentiveTrigger: { async deleteMany() {}, async createMany() {} },
    incentiveRule: { async deleteMany() {}, async createMany() {} },
    incentiveRewardDefinition: { async deleteMany() {}, async createMany() {} },
    incentiveBudget: {
      async deleteMany() {},
      async create({ data }) {
        budgets.push(data);
        return data;
      },
    },
  };
  const prisma = {
    incentiveCampaign: {
      async create({ data }) {
        assert(data.status === "DRAFT", "stored create status is draft");
        return { id: "camp-1", ...data, createdAt: new Date(), updatedAt: new Date() };
      },
    },
    $transaction: (work) => work(tx),
  };
  const repo = createPrismaRepository(prisma);
  const created = await repo.createCampaign({
    name: "Isolated",
    category: "REVIEW",
    priority: 0,
    stackingMode: "STACK",
    createdBy: actorId,
  });
  assert(created.status === "DRAFT", "prisma mapping returns draft");
  const version = await repo.createVersion({
    campaignId: created.id,
    versionNumber: 1,
    snapshot: { budget: { currency: "INR", amountCap: "10.00", issuedAmount: "9.00" }, rewards: [], triggers: [], audiences: [] },
    triggers: [],
    rules: [],
  });
  assert(budgets[0].issuedAmount === "0.00", "client issued amount is ignored");
  versions.get(version.id).publishedAt = new Date("2026-06-01T00:00:00.000Z");
  const beforeDeletes = deletes.length;
  await expectStatus(
    () => repo.saveVersion({ id: version.id, snapshot: { name: "tampered" }, publishedAt: null }),
    409
  );
  assert(deletes.length === beforeDeletes, "immutable save does not rewrite children");
  assert(prisma.coupon == null, "campaign repository does not use coupons");
  assert(prisma.order == null, "campaign repository does not use orders");
}

async function testHttpAuth() {
  const repo = createMemoryRepository();
  const app = express();
  app.use(express.json());
  app.use(
    "/incentive/admin",
    createAdminRouter({
      repository: repo,
      loadFlags: () => readFlags({ loadRows: async () => [] }),
      requireUser: testUser,
      requireAdmin,
      requireSuperAdmin,
    })
  );
  const server = await new Promise((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const missing = await jsonRequest(server, { method: "GET", requestPath: "/incentive/admin/campaigns" });
    assert(missing.status === 401, "admin route requires a user");
    const buyer = await jsonRequest(server, { method: "GET", requestPath: "/incentive/admin/campaigns", role: "buyer" });
    assert(buyer.status === 403, "buyer cannot read campaigns");
    const reader = await jsonRequest(server, {
      method: "POST",
      requestPath: "/incentive/admin/campaigns",
      role: "buyer",
      consoleAdmin: true,
      body: { name: "Nope", category: "REVIEW" },
    });
    assert(reader.status === 403, "console read access cannot write");
    const created = await jsonRequest(server, {
      method: "POST",
      requestPath: "/incentive/admin/campaigns",
      role: "super_admin",
      body: { name: "Portal draft", category: "LISTING", startsAt: "2026-02-01T00:00:00.000Z", endsAt: "2026-02-20T00:00:00.000Z" },
    });
    assert(created.status === 201, "super admin can create a draft");
    assert(created.json.status === "DRAFT", "http create stays draft");
    const listed = await jsonRequest(server, {
      method: "GET",
      requestPath: "/incentive/admin/campaigns",
      role: "buyer",
      consoleAdmin: true,
    });
    assert(listed.status === 200, "console admin can read");
    assert(listed.json.length === 1, "draft is listed");
    const blocked = await jsonRequest(server, {
      method: "POST",
      requestPath: `/incentive/admin/campaigns/${created.json.id}/activate`,
      role: "super_admin",
    });
    assert(blocked.status === 403, "http activation is blocked");
    assert(blocked.json.code === "ENGINE_DISABLED", "http activation reports the engine switch");
    const after = await jsonRequest(server, {
      method: "GET",
      requestPath: `/incentive/admin/campaigns/${created.json.id}`,
      role: "super_admin",
    });
    assert(after.json.status === "DRAFT", "http campaign remains draft");
    const flags = await readFlags({ loadRows: async () => [] });
    for (const key of Object.keys(ALL_OFF)) assert(flags[key] === false, `${key} remains off`);
    assert(repo.issued().rewards.length === 0, "http flow creates no rewards");
  } finally {
    await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
  }
}

function testSourceBoundaries() {
  const moduleRoot = path.join(__dirname, "../modules/incentive-engine");
  const files = [];
  (function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith(".js")) files.push(full);
    }
  })(moduleRoot);
  const source = files.map((file) => fs.readFileSync(file, "utf8")).join("\n");
  assert(!source.includes("eval("), "rules do not evaluate JavaScript");
  assert(!source.includes("new Function"), "rules do not build functions");
  assert(!source.includes("prisma.coupon"), "module does not write coupons");
  assert(
    !source.includes("prisma.order.create") &&
      !source.includes("prisma.order.update") &&
      !source.includes("prisma.order.delete"),
    "module does not write orders"
  );
  assert(!source.includes("incentiveSetting.create"), "module does not insert settings through create");
  assert(!source.includes("incentiveSetting.update"), "module does not update settings through update");
  const settingWriters = files.filter((file) => fs.readFileSync(file, "utf8").includes("incentiveSetting.upsert"));
  assert(
    settingWriters.length === 1 && settingWriters[0].endsWith(`${path.sep}configuration${path.sep}flags.js`),
    "only the flag module stores a switch"
  );
  const index = fs.readFileSync(path.join(moduleRoot, "index.js"), "utf8");
  assert(index.includes('router.use("/admin"'), "admin API is mounted under the incentive module");
  const migration = fs.readFileSync(
    path.join(__dirname, "../prisma/migrations/20261117120000_incentive_engine_foundation/migration.sql"),
    "utf8"
  );
  assert(!migration.includes("CREATE TRIGGER"), "Phase 2B did not add a ledger trigger");
  assert(!migration.toLowerCase().includes("drop table"), "foundation migration does not drop tables");
}

function activate(repo, campaignId, flags) {
  return service.changeStatus(repo, {
    campaignId,
    actorId,
    to: "ACTIVATE",
    flags,
    now: new Date("2026-06-01T00:00:00.000Z"),
  });
}

async function testReadiness() {
  const repo = createMemoryRepository();
  const draft = await createDraft(repo);
  await service.setAudiences(repo, { campaignId: draft.id, actorId, body: { audiences: [] } });
  const writes = repo.writes();
  const blockedAudience = await expectStatus(() => activate(repo, draft.id, enabledForTest), 400, "Add an audience");
  assert(blockedAudience.code === "AUDIENCE_REQUIRED", "empty audience blocks activation");
  assert(repo.writes() === writes, "rejected activation does not write");
  assert((await service.getCampaign(repo, draft.id)).status === "DRAFT", "empty audience stays a draft");

  const incomplete = await service.simulate(repo, {
    campaignId: draft.id,
    attributes: { "event.type": "ORDER_QUALIFIED" },
  });
  assert(incomplete.passed === false, "incomplete simulation does not pass");
  assert(incomplete.eligible === false, "incomplete simulation is not eligible");
  assert(incomplete.matchesEveryone === false, "an empty audience does not match everyone");
  assert(String(incomplete.reason).includes("audience"), incomplete.reason);
  assert(repo.writes() === writes, "incomplete simulation does not write");

  const mixed = await expectStatus(
    () => service.setAudiences(repo, {
      campaignId: draft.id,
      actorId,
      body: { audiences: [{ kind: "ALL_USERS" }, { kind: "BUYERS" }] },
    }),
    400,
    "cannot be combined"
  );
  assert(mixed.code === "AUDIENCE_COMBINATION", "ALL_USERS cannot be mixed");

  const allUsers = await createDraft(repo, { name: "Everyone" });
  await configure(repo, allUsers.id, {
    audiences: [{ kind: "ALL_USERS" }],
    eligibility: "AUDIENCE_AND_TRIGGER_ONLY",
  });
  const allSnapshot = (await service.getCampaign(repo, allUsers.id)).version.snapshot;
  const allReady = service.assessCampaign(allSnapshot);
  assert(allReady.ready === true, "ALL_USERS with audience and trigger policy is ready");
  assert(allReady.matchesEveryone === true, "ready ALL_USERS matches everyone");
  const allSim = await service.simulate(repo, {
    campaignId: allUsers.id,
    attributes: { "event.type": "ORDER_QUALIFIED", "user.role": "seller" },
  });
  assert(allSim.matchesEveryone === true, "simulation reports the explicit all-user audience");
  assert(allSim.passed === true, "explicit all-user sample passes");
  assert(allSim.audience.reason === "Explicit all-user audience", "all-user match is marked intentional");
  assert(allSim.rewards[0].issued === false, "all-user simulation does not issue a reward");
  const allOff = await expectStatus(() => activate(repo, allUsers.id, { ...ALL_OFF }), 403, "engine is off");
  assert(allOff.code === "ENGINE_DISABLED", "master off still blocks a ready campaign");
  assert((await service.getCampaign(repo, allUsers.id)).status === "DRAFT", "ready campaign stays draft while the engine is off");

  const rulesCampaign = await createDraft(repo, { name: "Rules" });
  await configure(repo, rulesCampaign.id);
  assert(service.assessCampaign((await service.getCampaign(repo, rulesCampaign.id)).version.snapshot).ready === true, "valid rules are accepted");
  const rulesOff = await expectStatus(() => activate(repo, rulesCampaign.id, { ...ALL_OFF }), 403);
  assert(rulesOff.code === "ENGINE_DISABLED", "a rules campaign is not activated while the engine is off");

  await expectStatus(
    () => service.setRules(repo, {
      campaignId: rulesCampaign.id,
      actorId,
      body: { eligibility: "RULES", rules: { combinator: "AND", conditions: [] } },
    }),
    400,
    "at least one condition"
  );
  const nullRules = await expectStatus(
    () => service.setRules(repo, { campaignId: rulesCampaign.id, actorId, body: { eligibility: "RULES", rules: null } }),
    400,
    "non-empty"
  );
  assert(nullRules.code === "RULES_REQUIRED", "a rules policy without a tree is rejected");
  const stored = await repo.getVersion((await service.getCampaign(repo, rulesCampaign.id)).currentVersionId);
  await repo.saveVersion({ ...stored, snapshot: { ...stored.snapshot, eligibility: "RULES", rules: null } });
  const activationEmpty = await expectStatus(() => activate(repo, rulesCampaign.id, enabledForTest), 400, "non-empty");
  assert(activationEmpty.code === "RULES_REQUIRED", "activation rejects a rules policy with no tree");
  assert((await service.getCampaign(repo, rulesCampaign.id)).status === "DRAFT", "invalid rules do not activate the campaign");

  const missingPolicy = await createDraft(repo, { name: "No policy" });
  await configure(repo, missingPolicy.id, { skipRules: true });
  const policyError = await expectStatus(() => activate(repo, missingPolicy.id, enabledForTest), 400, "eligibility policy");
  assert(policyError.code === "ELIGIBILITY_REQUIRED", "missing eligibility policy is rejected");

  const missingTrigger = await createDraft(repo, { name: "No trigger" });
  await configure(repo, missingTrigger.id, { triggers: [] });
  const triggerError = await expectStatus(() => activate(repo, missingTrigger.id, enabledForTest), 400, "trigger");
  assert(triggerError.code === "TRIGGER_REQUIRED", "missing trigger is rejected");

  const missingReward = await createDraft(repo, { name: "No reward" });
  await configure(repo, missingReward.id, { skipRewards: true });
  const rewardError = await expectStatus(() => activate(repo, missingReward.id, enabledForTest), 400, "reward");
  assert(rewardError.code === "REWARD_REQUIRED", "missing reward definition is rejected");

  const missingBudget = await createDraft(repo, { name: "No budget" });
  await configure(repo, missingBudget.id, { skipBudget: true });
  const budgetError = await expectStatus(() => activate(repo, missingBudget.id, enabledForTest), 400, "budget");
  assert(budgetError.code === "BUDGET_REQUIRED", "missing budget is rejected");

  assert(repo.issued().rewards.length === 0, "readiness creates no rewards");
  assert(repo.issued().ledger.length === 0, "readiness creates no ledger rows");
  assert(repo.issued().coupons.length === 0, "readiness creates no coupons");
  assert(repo.issued().referrals.length === 0, "readiness creates no referrals");
  assert(repo.issued().events.length === 0, "readiness creates no events");
}

async function main() {
  await testRules();
  await testCampaignLifecycle();
  await testSimulation();
  await testReadiness();
  await testPrismaRepositoryGuard();
  await testHttpAuth();
  testSourceBoundaries();
  console.log("incentive campaigns ok");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
