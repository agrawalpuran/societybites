const fs = require("fs");
const http = require("http");
const path = require("path");
const express = require("express");

const {
  ALL_OFF,
  FLAG_KEYS,
  effectiveFlags,
  readFlags,
  setWritableFlag,
} = require("../modules/incentive-engine/configuration/flags");
const { createFlagsRouter } = require("../modules/incentive-engine/routes/flags");
const { createAdminFlagsRouter } = require("../modules/incentive-engine/routes/adminFlags");
const incentiveRouter = require("../modules/incentive-engine");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function jsonRequest(server, { method, path: requestPath, body, headers }) {
  const address = server.address();
  const payload = body == null ? null : JSON.stringify(body);
  return new Promise((resolve, reject) => {
    const request = http.request(
      {
        hostname: "127.0.0.1",
        port: address.port,
        path: requestPath,
        method,
        headers: {
          Accept: "application/json",
          ...(payload
            ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) }
            : {}),
          ...(headers || {}),
        },
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

function memorySettings(initial = []) {
  const rows = initial.map((row) => ({ ...row }));
  const audits = [];
  const client = {
    rows,
    audits,
    $transaction: (fn) =>
      fn({
        incentiveSetting: {
          findUnique: async ({ where }) => rows.find((row) => row.key === where.key) || null,
          findMany: async () => rows.map((row) => ({ key: row.key, value: row.value })),
          upsert: async ({ where, create, update }) => {
            const found = rows.find((row) => row.key === where.key);
            if (found) {
              found.value = update.value;
              return found;
            }
            const created = { key: create.key, value: create.value };
            rows.push(created);
            return created;
          },
        },
        incentiveAuditLog: {
          create: async ({ data }) => {
            audits.push(data);
            return data;
          },
        },
      }),
  };
  return client;
}

function assertAllOff(flags, label) {
  for (const key of Object.keys(ALL_OFF)) {
    assert(flags[key] === false, `${label}: ${key} must stay off`);
  }
}

async function main() {
  assertAllOff(effectiveFlags(undefined), "missing rows");
  assertAllOff(effectiveFlags([]), "empty rows");
  assertAllOff(effectiveFlags(null), "null rows");

  const noisy = Object.values(FLAG_KEYS).map((key) => ({ key, value: "TRUE" }));
  noisy.push({ key: FLAG_KEYS.master, value: "1" });
  noisy.push({ key: FLAG_KEYS.issuance, value: "yes" });
  noisy.push({ key: "unknown", value: "true" });
  assertAllOff(effectiveFlags(noisy), "non-exact values");

  const childrenOnMasterOff = Object.values(FLAG_KEYS).map((key) => ({
    key,
    value: key === FLAG_KEYS.master ? "false" : "true",
  }));
  assertAllOff(effectiveFlags(childrenOnMasterOff), "master off");

  const referralChildrenWithoutReferral = [
    { key: FLAG_KEYS.master, value: "true" },
    { key: FLAG_KEYS.buyerReferral, value: "true" },
    { key: FLAG_KEYS.sellerReferral, value: "true" },
  ];
  const withoutReferral = effectiveFlags(referralChildrenWithoutReferral);
  assert(withoutReferral.master === true, "stored master true is visible to the helper");
  assert(withoutReferral.referral === false, "referral stays off");
  assert(withoutReferral.buyerReferral === false, "buyer referral requires referral");
  assert(withoutReferral.sellerReferral === false, "seller referral requires referral");
  assert(withoutReferral.issuance === false, "issuance stays off");
  assert(withoutReferral.redemption === false, "redemption stays off");

  for (const value of [" true ", "\ttrue", "true\n", "\r\ntrue\t", " \t\ntrue\r\n "]) {
    const enabled = effectiveFlags([
      { key: FLAG_KEYS.master, value },
      { key: FLAG_KEYS.issuance, value },
    ]);
    assert(enabled.issuance === true, `whitespace around true enables issuance (${JSON.stringify(value)})`);
  }
  for (const value of ["TRUE", "\tTRUE\n", "true\nfalse", "yes", "", "\u00A0true", null]) {
    const disabled = effectiveFlags([
      { key: FLAG_KEYS.master, value: "true" },
      { key: FLAG_KEYS.issuance, value },
    ]);
    assert(disabled.issuance === false, `only exact trimmed true enables issuance (${JSON.stringify(value)})`);
  }
  const missingIssuance = effectiveFlags([{ key: FLAG_KEYS.master, value: "true" }]);
  assert(missingIssuance.issuance === false, "a missing issuance setting stays off");

  const allStoredTrue = Object.values(FLAG_KEYS).map((key) => ({ key, value: " true " }));
  const allOn = effectiveFlags(allStoredTrue);
  for (const key of Object.keys(ALL_OFF)) {
    assert(allOn[key] === true, `trimmed true enables ${key} only inside the helper`);
  }

  let writes = 0;
  const failedRead = await readFlags({
    loadRows: async () => {
      const error = new Error("table missing");
      error.code = "P2021";
      throw error;
    },
  });
  assertAllOff(failedRead, "database failure");

  const noLoader = await readFlags();
  assertAllOff(noLoader, "no loader");

  const counted = await readFlags({
    loadRows: async () => {
      writes += 1;
      return [];
    },
  });
  assert(writes === 1, "flag read calls the loader once");
  assertAllOff(counted, "empty database");
  assert(writes === 1, "flag read does not write");

  const app = express();
  app.use(express.json());
  app.use("/incentive", incentiveRouter);
  const server = await new Promise((resolve) => {
    const listening = http.createServer(app);
    listening.listen(0, "127.0.0.1", () => resolve(listening));
  });

  try {
    const missingAuth = await jsonRequest(server, { method: "GET", path: "/incentive/flags" });
    assert(missingAuth.status === 401, "flags require a signed-in user");
    assert(
      missingAuth.json && missingAuth.json.error === "Missing or invalid Authorization header",
      "flags use the existing auth error"
    );

    const postFlags = await jsonRequest(server, { method: "POST", path: "/incentive/flags" });
    assert(postFlags.status === 404, "flags have no write route");

    const other = await jsonRequest(server, { method: "POST", path: "/incentive/campaigns" });
    assert(other.status === 404, "phase 2A does not mount campaign routes");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }

  const injected = express();
  injected.use(
    "/incentive",
    createFlagsRouter({
      requireUser: (req, _res, next) => {
        req.user = { id: "user-1" };
        next();
      },
      loadRows: async () => [],
    })
  );
  const injectedServer = await new Promise((resolve) => {
    const listening = http.createServer(injected);
    listening.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const flags = await jsonRequest(injectedServer, { method: "GET", path: "/incentive/flags" });
    assert(flags.status === 200, "signed-in flags request succeeds");
    assertAllOff(flags.json, "signed-in default flags");
  } finally {
    await new Promise((resolve) => injectedServer.close(resolve));
  }

  const migrationDir = path.join(__dirname, "..", "prisma", "migrations");
  const matches = fs
    .readdirSync(migrationDir)
    .filter((name) => name.endsWith("_incentive_engine_foundation"));
  assert(matches.length === 1, "exactly one incentive foundation migration");
  const sql = fs.readFileSync(path.join(migrationDir, matches[0], "migration.sql"), "utf8");
  assert(!/\bDROP\b/i.test(sql), "migration must not drop anything");
  assert(!/\bALTER TABLE "(User|Order|Listing|Coupon|AppSetting)"/i.test(sql), "migration must not alter protected tables");
  const created = [...sql.matchAll(/CREATE TABLE "([^"]+)"/g)].map((match) => match[1]);
  const expected = [
    "IncentiveSetting",
    "IncentiveCampaign",
    "IncentiveCampaignVersion",
    "IncentiveAudience",
    "IncentiveTrigger",
    "IncentiveRule",
    "IncentiveRewardDefinition",
    "IncentiveBudget",
    "IncentiveEvent",
    "IncentiveReferralCode",
    "IncentiveReferral",
    "IncentiveReward",
    "IncentiveLedgerEntry",
    "IncentiveRedemption",
    "IncentiveRiskEvaluation",
    "IncentiveApproval",
    "IncentiveAuditLog",
  ];
  assert(created.length === expected.length, "migration creates only the incentive tables");
  for (const name of expected) {
    assert(created.includes(name), `migration creates ${name}`);
  }
  for (const name of created) {
    assert(name.startsWith("Incentive"), `unexpected table ${name}`);
  }

  const indexSource = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
  assert(indexSource.includes('app.use("/incentive"'), "API mounts /incentive");

  const emptyStore = memorySettings();
  let rejected = false;
  try {
    await setWritableFlag(emptyStore, { actorId: "admin-1", key: "issuance", enabled: true });
  } catch (error) {
    rejected = error.code === "FLAG_NOT_WRITABLE";
  }
  assert(rejected, "issuance cannot be written");
  assert(emptyStore.rows.length === 0, "a rejected switch writes nothing");
  assert(emptyStore.audits.length === 0, "a rejected switch is not audited");

  for (const key of ["redemption", "promotional", "unknown"]) {
    let blocked = false;
    try {
      await setWritableFlag(emptyStore, { actorId: "admin-1", key, enabled: true });
    } catch (error) {
      blocked = error.code === "FLAG_NOT_WRITABLE";
    }
    assert(blocked, `${key} cannot be written`);
  }
  assert(emptyStore.rows.length === 0, "non-referral switches stay absent");

  let badValue = false;
  try {
    await setWritableFlag(emptyStore, { actorId: "admin-1", key: "referral", enabled: "true" });
  } catch (error) {
    badValue = error.code === "FLAG_VALUE_INVALID";
  }
  assert(badValue, "a string value is rejected");
  assert(emptyStore.rows.length === 0, "an invalid value writes nothing");

  const turnedOn = await setWritableFlag(emptyStore, { actorId: "admin-1", key: "referral", enabled: true });
  assert(turnedOn.stored.referral === true, "referral is stored on");
  assert(turnedOn.referral === false, "referral stays off while master is off");
  assert(turnedOn.master === false, "master stays off by default");
  assert(turnedOn.issuance === false, "issuance stays off");
  assert(emptyStore.rows.length === 1, "only the referral row is stored");
  assert(emptyStore.rows[0].value === "true", "the stored value is the exact text true");
  assert(emptyStore.audits.length === 1 && emptyStore.audits[0].action === "FLAG_CHANGED", "a change is audited");

  const repeat = await setWritableFlag(emptyStore, { actorId: "admin-1", key: "referral", enabled: true });
  assert(repeat.stored.referral === true, "repeating the same value keeps it on");
  assert(emptyStore.audits.length === 1, "an unchanged switch is not audited again");

  const turnedOff = await setWritableFlag(emptyStore, { actorId: "admin-1", key: "referral", enabled: false });
  assert(turnedOff.stored.referral === false, "referral is stored off");
  assert(turnedOff.referral === false, "effective referral is off");
  assert(emptyStore.rows[0].value === "false", "off is stored as the exact text false");
  assert(emptyStore.audits.length === 2, "turning a switch off is audited");

  const withMaster = memorySettings([{ key: FLAG_KEYS.master, value: "true" }]);
  const buyerOn = await setWritableFlag(withMaster, { actorId: "admin-1", key: "buyerReferral", enabled: true });
  assert(buyerOn.stored.buyerReferral === true, "buyer referral is stored");
  assert(buyerOn.buyerReferral === false, "buyer referral still needs the referral switch");
  await setWritableFlag(withMaster, { actorId: "admin-1", key: "referral", enabled: true });
  const ready = await setWritableFlag(withMaster, { actorId: "admin-1", key: "master", enabled: true });
  assert(ready.master === true && ready.referral === true && ready.buyerReferral === true, "master, referral, and buyer referral are on together");
  assert(ready.sellerReferral === false && ready.issuance === false, "seller referral and issuance stay off");

  const flagApp = express();
  flagApp.use(express.json());
  flagApp.use(
    "/incentive/admin",
    createAdminFlagsRouter({
      writeFlag: (input) => setWritableFlag(memorySettings(), input),
      requireUser: (req, res, next) => {
        const role = req.header("x-role");
        if (!role) return res.status(401).json({ error: "Missing or invalid Authorization header" });
        req.user = { id: "admin-1", role };
        next();
      },
      requireSuperAdmin: (req, res, next) => {
        if (!req.user || req.user.role !== "super_admin") {
          return res.status(403).json({ error: "Super admin access required" });
        }
        next();
      },
    })
  );
  const flagServer = await new Promise((resolve) => {
    const listening = http.createServer(flagApp);
    listening.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const missing = await jsonRequest(flagServer, {
      method: "PUT",
      path: "/incentive/admin/flags",
      body: { key: "referral", enabled: true },
    });
    assert(missing.status === 401, "a flag write requires a signed-in user");

    const portal = await jsonRequest(flagServer, {
      method: "PUT",
      path: "/incentive/admin/flags",
      body: { key: "referral", enabled: true },
      headers: { "x-role": "buyer" },
    });
    assert(portal.status === 403, "a console admin cannot change a switch");

    const blocked = await jsonRequest(flagServer, {
      method: "PUT",
      path: "/incentive/admin/flags",
      body: { key: "issuance", enabled: true },
      headers: { "x-role": "super_admin" },
    });
    assert(blocked.status === 400 && blocked.json && blocked.json.code === "FLAG_NOT_WRITABLE", "issuance stays without a writer");

    const saved = await jsonRequest(flagServer, {
      method: "PUT",
      path: "/incentive/admin/flags",
      body: { key: "sellerReferral", enabled: false },
      headers: { "x-role": "super_admin" },
    });
    assert(saved.status === 200 && saved.json && saved.json.sellerReferral === false, "saving off leaves the switch off");
    assert(saved.json.stored && saved.json.stored.sellerReferral === false, "the stored seller switch is off");
    assert(saved.json.issuance === false && saved.json.master === false, "other switches stay off");
  } finally {
    await new Promise((resolve) => flagServer.close(resolve));
  }

  console.log("incentive flags ok");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
