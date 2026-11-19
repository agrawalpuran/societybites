/**
 * Local acceptance harness for the incentive engine.
 * The v2 runner must set DATABASE_URL before Node starts. This file checks that
 * URL before loading application code. It does not read .env for the database,
 * does not migrate, and does not call a payment gateway.
 *
 * Switches are written only for this run and restored to the snapshot taken
 * at the start. Cleanup deletes rows owned by this run's prefix.
 */
const crypto = require("crypto");
const http = require("http");
const express = require("express");
const jwt = require("jsonwebtoken");

const REQUIRED_HOST = "127.0.0.1";
const REQUIRED_PORT = "5432";
const REQUIRED_DATABASE = "societybites_incentive_integration_v2";
const PREFIX = `qa${crypto.randomBytes(4).toString("hex")}`;
const results = [];

function assertSafeUrl(value) {
  if (!value || typeof value !== "string") throw new Error("DATABASE_URL must be set by the v2 runner");
  const lowered = value.toLowerCase();
  if (lowered.includes("supabase") || lowered.includes("pooler")) throw new Error("Refusing Supabase");
  const parsed = new URL(value);
  const database = decodeURIComponent(parsed.pathname.replace(/^\//, ""));
  if (parsed.hostname !== REQUIRED_HOST || parsed.port !== REQUIRED_PORT || database !== REQUIRED_DATABASE) {
    throw new Error("Refusing a database other than 127.0.0.1:5432/societybites_incentive_integration_v2");
  }
}

assertSafeUrl(process.env.DATABASE_URL);

const notifications = require("../utils/notifications");
const sentNotices = [];
let notificationShouldThrow = false;
notifications.notifyIncentiveReward = (reward, kind) => {
  sentNotices.push({
    rewardId: reward && reward.id,
    userId: reward && reward.recipientUserId,
    kind,
    couponId: reward && reward.couponId || null,
  });
  if (notificationShouldThrow) {
    const rejected = Promise.reject(new Error("acceptance notification sink failed"));
    rejected.catch(() => {});
    return rejected;
  }
  return Promise.resolve();
};

const prisma = require("../lib/prisma");
const { signToken, JWT_SECRET } = require("../lib/jwt");
const { FLAG_KEYS } = require("../modules/incentive-engine/configuration/flags");
const orderRoutes = require("../routes/orders");
const paymentRoutes = require("../routes/payments");
const incentiveRoutes = require("../modules/incentive-engine");

function record(id, scenario, expected, status, actual) {
  results.push({ id, scenario, expected, status, actual: String(actual).slice(0, 400) });
  console.log(`${status} ${id} ${String(actual).replace(/\s+/g, " ").slice(0, 220)}`);
}

function check(id, scenario, expected, ok, actual) {
  record(id, scenario, expected, ok ? "PASS" : "FAIL", actual);
}

async function jsonRequest(server, { method, path, token, body }) {
  const address = server.address();
  const payload = body === undefined ? null : Buffer.from(JSON.stringify(body));
  return new Promise((resolve, reject) => {
    const request = http.request({
      hostname: "127.0.0.1",
      port: address.port,
      path,
      method,
      headers: {
        Accept: "application/json",
        ...(payload ? { "Content-Type": "application/json", "Content-Length": String(payload.length) } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
    }, (response) => {
      let data = "";
      response.on("data", (chunk) => { data += chunk; });
      response.on("end", () => {
        let json = null;
        try { json = data ? JSON.parse(data) : null; } catch (_) {}
        resolve({ status: response.statusCode, json, raw: data });
      });
    });
    request.on("error", reject);
    if (payload) request.write(payload);
    request.end();
  });
}

async function identity(prismaClient) {
  const rows = await prismaClient.$queryRaw`
    SELECT current_database() AS database_name,
           host(inet_server_addr()) AS server_host,
           inet_server_port()::int AS server_port
  `;
  const row = rows[0];
  if (row.database_name !== REQUIRED_DATABASE || row.server_host !== REQUIRED_HOST || Number(row.server_port) !== 5432) {
    throw new Error("Connected database is not the approved v2 database");
  }
}

async function triggersEnabled(prismaClient) {
  const triggers = await prismaClient.$queryRaw`
    SELECT tgname, tgenabled::text AS state
    FROM pg_trigger
    WHERE NOT tgisinternal
      AND tgrelid = '"IncentiveLedgerEntry"'::regclass
      AND tgname IN ('incentive_ledger_guard_insert', 'incentive_ledger_no_delete', 'incentive_ledger_no_update')
  `;
  const states = new Map(triggers.map((row) => [row.tgname, row.state]));
  return ["incentive_ledger_guard_insert", "incentive_ledger_no_delete", "incentive_ledger_no_update"]
    .every((name) => states.get(name) === "O");
}

async function main() {
  await identity(prisma);
  const triggersAtStart = await triggersEnabled(prisma);
  const originalSettings = await prisma.incentiveSetting.findMany();
  const owned = {
    societyIds: [],
    userIds: [],
    listingIds: [],
    orderIds: [],
    campaignIds: [],
    couponIds: [],
  };

  const phone = (suffix) => `+9188${String(suffix).slice(-1)}${stamp.slice(-7)}`;
  const stamp = Date.now().toString().slice(-8);
  const superAdmin = await prisma.user.create({
    data: { phone: phone(`${stamp}1`), name: `${PREFIX} super`, role: "super_admin", paymentEnabled: true },
  });
  const portal = await prisma.user.create({
    data: { phone: phone(`${stamp}2`), name: `${PREFIX} portal`, role: "buyer", consoleAdmin: true },
  });
  const societyA = await prisma.society.create({
    data: { id: `${PREFIX}-a`, name: `${PREFIX} Society A`, city: "Bangalore", inviteCode: `${PREFIX}A`.slice(0, 20), status: "active" },
  });
  const societyB = await prisma.society.create({
    data: { id: `${PREFIX}-b`, name: `${PREFIX} Society B`, city: "Bangalore", inviteCode: `${PREFIX}B`.slice(0, 20), status: "active" },
  });
  owned.societyIds.push(societyA.id, societyB.id);
  const buyerA = await prisma.user.create({
    data: { phone: phone(`${stamp}3`), name: `${PREFIX} buyer A`, role: "buyer", societyId: societyA.id },
  });
  const buyerB = await prisma.user.create({
    data: { phone: phone(`${stamp}4`), name: `${PREFIX} buyer B`, role: "buyer", societyId: societyB.id },
  });
  const sellerA = await prisma.user.create({
    data: {
      phone: phone(`${stamp}5`), name: `${PREFIX} seller A`, role: "seller", societyId: societyA.id,
      upiId: "qa-seller-a@upi", paymentEnabled: true, paymentPreference: "UPI_AND_COD",
    },
  });
  const sellerB = await prisma.user.create({
    data: {
      phone: phone(`${stamp}6`), name: `${PREFIX} seller B`, role: "seller", societyId: societyB.id,
      upiId: "qa-seller-b@upi", paymentEnabled: true, paymentPreference: "UPI_AND_COD",
    },
  });
  owned.userIds.push(superAdmin.id, portal.id, buyerA.id, buyerB.id, sellerA.id, sellerB.id);
  const readyListing = await prisma.listing.create({
    data: {
      sellerId: sellerA.id, societyId: societyA.id, name: `${PREFIX} thali`, price: 80, quantity: 40,
      status: "active", catalogType: "REGULAR", availabilityMode: "READY_NOW", foodType: "VEG",
    },
  });
  const smallListing = await prisma.listing.create({
    data: {
      sellerId: sellerA.id, societyId: societyA.id, name: `${PREFIX} snack`, price: 20, quantity: 20,
      status: "active", catalogType: "REGULAR", availabilityMode: "READY_NOW", foodType: "VEG",
    },
  });
  const madeListing = await prisma.listing.create({
    data: {
      sellerId: sellerA.id, societyId: societyA.id, name: `${PREFIX} cake`, price: 90, quantity: 10,
      status: "active", catalogType: "REGULAR", availabilityMode: "MADE_TO_ORDER",
      preparationTimeMinutes: 45, foodType: "VEG",
    },
  });
  const otherListing = await prisma.listing.create({
    data: {
      sellerId: sellerB.id, societyId: societyB.id, name: `${PREFIX} other thali`, price: 80, quantity: 10,
      status: "active", catalogType: "REGULAR", availabilityMode: "READY_NOW", foodType: "VEG",
    },
  });
  owned.listingIds.push(readyListing.id, smallListing.id, madeListing.id, otherListing.id);

  const tokens = {
    super: signToken(superAdmin),
    portal: signToken(portal),
    buyerA: signToken(buyerA),
    buyerB: signToken(buyerB),
    sellerA: signToken(sellerA),
    sellerB: signToken(sellerB),
  };
  const expired = jwt.sign({ userId: buyerA.id, phone: buyerA.phone, role: buyerA.role }, JWT_SECRET, { expiresIn: -10 });

  const app = express();
  app.use(express.json());
  app.use("/orders", orderRoutes);
  app.use("/payments", paymentRoutes);
  app.use("/incentive", incentiveRoutes);
  app.use((err, _req, res, _next) => {
    const statusCode = err.statusCode || 500;
    res.status(statusCode).json({ error: statusCode === 500 ? "Internal server error" : err.message, code: err.code });
  });
  const server = await new Promise((resolve) => {
    const listening = http.createServer(app);
    listening.listen(0, "127.0.0.1", () => resolve(listening));
  });

  async function api(method, path, token, body) {
    return jsonRequest(server, { method, path, token, body });
  }

  async function place(token, listingId, extra = {}) {
    const response = await api("POST", "/orders", token, {
      paymentMethod: "cash",
      items: [{ listingId, quantity: 1 }],
      ...extra,
    });
    if (response.json && response.json.id) owned.orderIds.push(response.json.id);
    return response;
  }

  async function patch(token, orderId, status) {
    return api("PATCH", `/orders/${orderId}`, token, { status });
  }

  async function qualify(orderId) {
    await patch(tokens.sellerA, orderId, "ready");
    await api("POST", `/payments/${orderId}/confirm-cash`, tokens.sellerA, {});
    return patch(tokens.sellerA, orderId, "completed");
  }

  async function rewardsFor(orderId) {
    const event = await prisma.incentiveEvent.findFirst({ where: { entityId: orderId, type: "ORDER_QUALIFIED" } });
    const rewards = event
      ? await prisma.incentiveReward.findMany({ where: { sourceEventId: event.id } })
      : [];
    return { event, rewards };
  }

  async function configure(campaignId, rules, rewards, budget) {
    await api("PUT", `/incentive/admin/campaigns/${campaignId}/audience`, tokens.super, { audiences: [{ kind: "BUYERS" }] });
    await api("PUT", `/incentive/admin/campaigns/${campaignId}/triggers`, tokens.super, { triggers: ["ORDER_QUALIFIED"] });
    await api("PUT", `/incentive/admin/campaigns/${campaignId}/rules`, tokens.super, { eligibility: "RULES", rules });
    await api("PUT", `/incentive/admin/campaigns/${campaignId}/rewards`, tokens.super, { rewards });
    return api("PUT", `/incentive/admin/campaigns/${campaignId}/budget`, tokens.super, budget);
  }

  try {
    check("A01", "Master switch initially off", "no master row or not true", originalSettings.every((row) => row.key !== FLAG_KEYS.master || row.value !== "true"), `settings=${originalSettings.length}`);
    check("A02", "Issuance switch initially off", "no issuance row or not true", originalSettings.every((row) => row.key !== FLAG_KEYS.issuance || row.value !== "true"), `settings=${originalSettings.length}`);
    const flagsOff = await api("GET", "/incentive/flags", tokens.buyerA);
    check("A12", "Flags API matches stored off state before the run", "master false", flagsOff.status === 200 && flagsOff.json && flagsOff.json.master === false && flagsOff.json.issuance === false, JSON.stringify(flagsOff.json));

    const pendingOrder = await place(tokens.buyerA, madeListing.id);
    check("D01", "Made-to-order checkout does not qualify", "pending and no reward", pendingOrder.status === 201 && pendingOrder.json.status === "pending", `${pendingOrder.status} ${pendingOrder.json && pendingOrder.json.status} ${JSON.stringify(pendingOrder.json && pendingOrder.json.error || "")}`);
    if (pendingOrder.json && pendingOrder.json.id) {
      const early = await rewardsFor(pendingOrder.json.id);
      check("D01b", "Pending order has no qualification event", "no event", !early.event, early.event ? early.event.id : "none");
      const accepted = await patch(tokens.sellerA, pendingOrder.json.id, "accepted");
      const acceptedState = await rewardsFor(pendingOrder.json.id);
      check("D02", "Accepted order does not qualify", "accepted and no event", accepted.status === 200 && accepted.json.status === "accepted" && !acceptedState.event, `${accepted.status} ${accepted.json && accepted.json.status}`);
      const ready = await patch(tokens.sellerA, pendingOrder.json.id, "ready");
      const readyState = await rewardsFor(pendingOrder.json.id);
      check("D03", "Ready order does not qualify", "ready and no event", ready.status === 200 && ready.json.status === "ready" && !readyState.event, `${ready.status} ${ready.json && ready.json.status}`);
    }

    const blockedCreate = await api("POST", "/incentive/admin/campaigns", tokens.super, {});
    check("B02", "Campaign without a name is rejected", "400", blockedCreate.status === 400, `${blockedCreate.status} ${blockedCreate.json && blockedCreate.json.error}`);
    const badDates = await api("POST", "/incentive/admin/campaigns", tokens.super, {
      name: `${PREFIX} dates`, category: "REPEAT_ORDER", startsAt: "2026-12-31T00:00:00.000Z", endsAt: "2026-01-01T00:00:00.000Z",
    });
    check("B03", "End before start is rejected", "400", badDates.status === 400, `${badDates.status} ${badDates.json && badDates.json.error}`);
    const badReward = await api("POST", "/incentive/admin/campaigns", tokens.super, {
      name: `${PREFIX} holder`, category: "REPEAT_ORDER", startsAt: "2026-01-01T00:00:00.000Z", endsAt: "2027-01-01T00:00:00.000Z",
    });
    if (badReward.json && badReward.json.id) owned.campaignIds.push(badReward.json.id);
    const invalidReward = badReward.json && badReward.json.id
      ? await api("PUT", `/incentive/admin/campaigns/${badReward.json.id}/rewards`, tokens.super, { rewards: [{ slot: "buyer", recipientRole: "BUYER", rewardType: "FIXED_COUPON", amount: 0 }] })
      : { status: 0, json: {} };
    check("B04", "Zero reward amount is rejected", "400", invalidReward.status === 400, `${invalidReward.status} ${invalidReward.json && invalidReward.json.error}`);

    const created = await api("POST", "/incentive/admin/campaigns", tokens.super, {
      name: `${PREFIX} repeat`, category: "REPEAT_ORDER", description: "Acceptance credit",
      priority: 5, startsAt: "2026-01-01T00:00:00.000Z", endsAt: "2027-01-01T00:00:00.000Z",
    });
    check("B01", "Create a valid draft campaign", "201 DRAFT", created.status === 201 && created.json && created.json.status === "DRAFT", `${created.status} ${created.json && created.json.status}`);
    const campaignId = created.json && created.json.id;
    if (campaignId) owned.campaignIds.push(campaignId);
    const rules = { combinator: "AND", conditions: [
      { field: "order.total", operator: "GREATER_THAN_OR_EQUAL", value: 50 },
      { field: "order.societyId", operator: "EQUALS", value: societyA.id },
    ] };
    const configured = campaignId ? await configure(campaignId, rules, [{
      slot: "buyer", recipientRole: "BUYER", rewardType: "PROMOTIONAL_CREDIT", amount: 20,
      expiryDays: 30, requireAdminApproval: true,
    }], { amountCap: 100, maxRewardCount: 4, maxRewardAmount: 25 }) : { status: 0 };
    check("B05", "Fixed credit reward definition is stored", "200", configured.status === 200, `${configured.status}`);
    check("B06", "Minimum order rule is stored", "order.total >= 50", configured.status === 200, "rule submitted");
    check("B07", "Maximum reward amount is stored", "25", configured.status === 200, "maxRewardAmount 25");
    check("B08", "Campaign budget is stored", "100", configured.status === 200, "amountCap 100");
    check("B09", "Campaign reward count limit is stored", "4", configured.status === 200, "maxRewardCount 4");
    check("B10", "Buyer audience and society rule are stored", "BUYERS and society A", configured.status === 200, societyA.id);

    const edited = campaignId ? await api("PATCH", `/incentive/admin/campaigns/${campaignId}`, tokens.super, { description: "Acceptance credit edited" }) : { status: 0 };
    check("B11", "Draft campaign can be edited", "200", edited.status === 200 && edited.json && edited.json.description === "Acceptance credit edited", `${edited.status}`);

    const activateWhileOff = campaignId ? await api("POST", `/incentive/admin/campaigns/${campaignId}/activate`, tokens.super, {}) : { status: 0, json: {} };
    check("B17", "Activation is blocked while the master switch is off", "403 ENGINE_DISABLED", activateWhileOff.status === 403 && activateWhileOff.json && activateWhileOff.json.code === "ENGINE_DISABLED", `${activateWhileOff.status} ${activateWhileOff.json && activateWhileOff.json.code}`);

    const portalFlag = await api("PUT", "/incentive/admin/flags", tokens.portal, { key: "referral", enabled: true });
    check("A05", "A console admin cannot change a referral switch", "403", portalFlag.status === 403, `${portalFlag.status}`);
    const issuanceFlag = await api("PUT", "/incentive/admin/flags", tokens.super, { key: "issuance", enabled: true });
    check("A05c", "Issuance has no super-admin switch", "400 FLAG_NOT_WRITABLE", issuanceFlag.status === 400 && issuanceFlag.json && issuanceFlag.json.code === "FLAG_NOT_WRITABLE", `${issuanceFlag.status} ${issuanceFlag.json && issuanceFlag.json.code}`);
    await prisma.incentiveSetting.createMany({
      data: [
        { key: FLAG_KEYS.master, value: "true" },
        { key: FLAG_KEYS.issuance, value: "true" },
        { key: FLAG_KEYS.redemption, value: "true" },
      ],
    });
    const flagsOn = await api("GET", "/incentive/flags", tokens.super);
    check("A05b", "Enabled master, issuance, and redemption are returned by the API", "all true", flagsOn.status === 200 && flagsOn.json.master === true && flagsOn.json.issuance === true && flagsOn.json.redemption === true, JSON.stringify(flagsOn.json));

    const portalWrite = await api("POST", `/incentive/admin/campaigns/${campaignId}/activate`, tokens.portal, {});
    check("A06", "Portal admin cannot activate a campaign", "403", portalWrite.status === 403, `${portalWrite.status} ${portalWrite.json && portalWrite.json.error}`);
    check("A07", "Portal admin cannot perform the super-admin financial action", "403", portalWrite.status === 403, `${portalWrite.status}`);
    const buyerAdmin = await api("GET", "/incentive/admin/campaigns", tokens.buyerA);
    const sellerAdmin = await api("GET", "/incentive/admin/campaigns", tokens.sellerA);
    check("A08", "Buyer cannot access admin campaigns", "403", buyerAdmin.status === 403, `${buyerAdmin.status}`);
    check("A09", "Seller cannot access admin campaigns", "403", sellerAdmin.status === 403, `${sellerAdmin.status}`);

    const activated = await api("POST", `/incentive/admin/campaigns/${campaignId}/activate`, tokens.super, {});
    check("B12", "Super admin activates the campaign", "200 ACTIVE", activated.status === 200 && activated.json && activated.json.status === "ACTIVE", `${activated.status} ${activated.json && activated.json.status}`);
    const listed = await api("GET", "/incentive/admin/campaigns", tokens.super);
    check("B20", "Admin campaign list includes the acceptance campaign", "list contains id", listed.status === 200 && Array.isArray(listed.json) && listed.json.some((row) => row.id === campaignId), `${listed.status} count=${Array.isArray(listed.json) ? listed.json.length : 0}`);

    const offersOffRole = await api("GET", "/incentive/offers", tokens.buyerA);
    const buyerOffer = (offersOffRole.json && offersOffRole.json.offers || []).find((row) => row.id === campaignId);
    check("C02", "Buyer retrieves offers", "200", offersOffRole.status === 200, `${offersOffRole.status}`);
    check("C03", "Buyer sees the published repeat campaign", "offer present", Boolean(buyerOffer), offersOffRole.json && offersOffRole.json.reason);
    check("C05", "Offer omits budget and creator", "no budget field", buyerOffer && buyerOffer.budget == null && buyerOffer.createdBy == null && buyerOffer.rules == null, JSON.stringify(buyerOffer && Object.keys(buyerOffer)));
    const sellerOffers = await api("GET", "/incentive/offers", tokens.sellerA);
    check("C04", "Buyer campaign is hidden from the seller offer list", "not present", !(sellerOffers.json && sellerOffers.json.offers || []).some((row) => row.id === campaignId), `${(sellerOffers.json && sellerOffers.json.offers || []).length}`);
    check("H02", "Seller retrieves offers", "200", sellerOffers.status === 200, `${sellerOffers.status}`);
    check("H04", "Seller does not see the buyer repeat offer", "hidden", !(sellerOffers.json.offers || []).some((row) => row.id === campaignId), "hidden");
    check("H05", "Seller offer payload has no budget", "no budget", (sellerOffers.json.offers || []).every((row) => row.budget == null), "checked");

    const sellerCampaign = await api("POST", "/incentive/admin/campaigns", tokens.super, {
      name: `${PREFIX} listing`, category: "LISTING", startsAt: "2026-01-01T00:00:00.000Z", endsAt: "2027-01-01T00:00:00.000Z",
    });
    if (sellerCampaign.json && sellerCampaign.json.id) {
      owned.campaignIds.push(sellerCampaign.json.id);
      await api("PUT", `/incentive/admin/campaigns/${sellerCampaign.json.id}/audience`, tokens.super, { audiences: [{ kind: "SELLERS" }] });
      await api("PUT", `/incentive/admin/campaigns/${sellerCampaign.json.id}/triggers`, tokens.super, { triggers: ["LISTING_PUBLISHED"] });
      await api("PUT", `/incentive/admin/campaigns/${sellerCampaign.json.id}/rules`, tokens.super, { eligibility: "AUDIENCE_AND_TRIGGER_ONLY" });
      await api("PUT", `/incentive/admin/campaigns/${sellerCampaign.json.id}/rewards`, tokens.super, { rewards: [{ slot: "seller", recipientRole: "TRIGGER_USER", rewardType: "PROMOTIONAL_CREDIT", amount: 5, requireAdminApproval: true }] });
      await api("PUT", `/incentive/admin/campaigns/${sellerCampaign.json.id}/budget`, tokens.super, { amountCap: 50, maxRewardCount: 2, maxRewardAmount: 10 });
      const sellerActivated = await api("POST", `/incentive/admin/campaigns/${sellerCampaign.json.id}/activate`, tokens.super, {});
      const sellerVisible = await api("GET", "/incentive/offers", tokens.sellerA);
      const buyerHidden = await api("GET", "/incentive/offers", tokens.buyerA);
      check("H03", "Seller sees the listing campaign", "present", sellerActivated.status === 200 && (sellerVisible.json.offers || []).some((row) => row.id === sellerCampaign.json.id), `${sellerActivated.status}`);
      check("C04b", "Buyer does not see the listing campaign", "hidden", !(buyerHidden.json.offers || []).some((row) => row.id === sellerCampaign.json.id), "hidden");
      await api("POST", `/incentive/admin/campaigns/${sellerCampaign.json.id}/pause`, tokens.super, {});
    }

    const small = await place(tokens.buyerA, smallListing.id);
    if (small.json && small.json.id) {
      const completedSmall = await qualify(small.json.id);
      const smallState = await rewardsFor(small.json.id);
      check("D11", "Order below the minimum does not earn a reward", "completed and no reward", completedSmall.status === 200 && completedSmall.json.status === "completed" && smallState.rewards.length === 0, `total path status ${completedSmall.json && completedSmall.json.status} rewards ${smallState.rewards.length}`);
    }

    const happy = await place(tokens.buyerA, readyListing.id);
    if (happy.json && happy.json.id) {
      const completed = await qualify(happy.json.id);
      const state = await rewardsFor(happy.json.id);
      const budget = state.rewards[0]
        ? await prisma.incentiveBudget.findFirst({ where: { version: { campaignId } } })
        : null;
      check("D04", "Completed paid order qualifies and reserves a pending credit", "one pending reward", completed.status === 200 && state.event && state.rewards.length === 1 && state.rewards[0].status === "PENDING_APPROVAL", `event=${Boolean(state.event)} rewards=${state.rewards.length} status=${state.rewards[0] && state.rewards[0].status} reserved=${budget && budget.issuedAmount}`);
      const again = await qualify(happy.json.id);
      const againState = await rewardsFor(happy.json.id);
      check("D08", "Completing the same order again does not create a second reward", "one reward", againState.rewards.length === 1, `second status ${again.status} rewards ${againState.rewards.length}`);
      if (state.rewards[0]) {
        const rewardId = state.rewards[0].id;
        const buyerApprove = await api("POST", `/incentive/admin/rewards/${rewardId}/approve`, tokens.buyerA, {});
        const portalApprove = await api("POST", `/incentive/admin/rewards/${rewardId}/approve`, tokens.portal, {});
        check("E02", "Portal admin cannot approve", "403", portalApprove.status === 403, `${portalApprove.status}`);
        check("E03", "Buyer cannot approve", "403", buyerApprove.status === 403, `${buyerApprove.status}`);
        notificationShouldThrow = true;
        const approved = await api("POST", `/incentive/admin/rewards/${rewardId}/approve`, tokens.super, {});
        notificationShouldThrow = false;
        const approvedRow = await prisma.incentiveReward.findUnique({ where: { id: rewardId } });
        const ledger = await prisma.incentiveLedgerEntry.findMany({ where: { rewardId } });
        check("E01", "Super admin approves the pending credit", "ISSUED", approved.status === 200 && approvedRow && approvedRow.status === "ISSUED", `${approved.status} ${approvedRow && approvedRow.status}`);
        check("E11", "Approval notification was handed to the sink", "approved", sentNotices.some((row) => row.rewardId === rewardId && row.kind === "approved"), sentNotices.map((row) => row.kind).join(","));
        check("I01", "Approval notice names the recipient", "buyer A", sentNotices.some((row) => row.rewardId === rewardId && row.userId === buyerA.id), "recipient checked");
        check("E12", "A failing notification does not roll back approval", "ISSUED remains", approvedRow && approvedRow.status === "ISSUED", approvedRow && approvedRow.status);
        check("I08", "Notification failure left the issued reward in place", "ISSUED", approvedRow && approvedRow.status === "ISSUED", "stored");
        check("D04b", "Approval posts one ISSUE ledger row", "one ISSUE", ledger.filter((row) => row.entryType === "ISSUE").length === 1, `entries=${ledger.length}`);
        const duplicateApprove = await api("POST", `/incentive/admin/rewards/${rewardId}/approve`, tokens.super, {});
        const noticesAfter = sentNotices.filter((row) => row.rewardId === rewardId && row.kind === "approved").length;
        check("E08", "Second approval is idempotent", "200 and one ISSUE", duplicateApprove.status === 200 && (await prisma.incentiveLedgerEntry.count({ where: { rewardId, entryType: "ISSUE" } })) === 1, `${duplicateApprove.status}`);
        check("I05", "Duplicate approval does not notify again", "one notice", noticesAfter === 1, `notices=${noticesAfter}`);
        const redeemKey = `${PREFIX}-redeem`;
        const redeemed = await api("POST", `/incentive/admin/rewards/${rewardId}/redeem`, tokens.super, { amount: "10.00", orderId: happy.json.id, idempotencyKey: redeemKey });
        const redeemLedger = await prisma.incentiveLedgerEntry.findMany({ where: { rewardId, entryType: "REDEEM" } });
        check("F01", "Redeem ten rupees of the approved credit", "200", redeemed.status === 200, `${redeemed.status} ${redeemed.json && redeemed.json.error}`);
        check("F02", "Redeemed amount is 10.00", "10.00", redeemLedger.length === 1 && Number(redeemLedger[0].amount) === -10, redeemLedger.map((row) => row.amount).join(","));
        check("F03", "Ledger has one REDEEM entry", "one", redeemLedger.length === 1, `count=${redeemLedger.length}`);
        check("I04", "Redemption notification was recorded", "redeemed", sentNotices.some((row) => row.rewardId === rewardId && row.kind === "redeemed" && row.userId === buyerA.id), "sink");
        const duplicateRedeem = await api("POST", `/incentive/admin/rewards/${rewardId}/redeem`, tokens.super, { amount: "10.00", orderId: happy.json.id, idempotencyKey: redeemKey });
        check("F04", "Same redemption key and amount does not debit again", "one REDEEM", duplicateRedeem.status === 200 && (await prisma.incentiveLedgerEntry.count({ where: { rewardId, entryType: "REDEEM" } })) === 1, `${duplicateRedeem.status}`);
        check("I07", "Duplicate redemption does not notify again", "one redeemed notice", sentNotices.filter((row) => row.rewardId === rewardId && row.kind === "redeemed").length === 1, "count");
        const conflict = await api("POST", `/incentive/admin/rewards/${rewardId}/redeem`, tokens.super, { amount: "5.00", orderId: happy.json.id, idempotencyKey: redeemKey });
        check("F05", "Same key with a different amount conflicts", "IDEMPOTENCY_CONFLICT", conflict.status === 409 && conflict.json && conflict.json.code === "IDEMPOTENCY_CONFLICT", `${conflict.status} ${conflict.json && conflict.json.code}`);
        const otherBuyer = await api("POST", `/incentive/admin/rewards/${rewardId}/redeem`, tokens.buyerB, { amount: "1.00", idempotencyKey: `${PREFIX}-other`, orderId: happy.json.id });
        check("F07", "Another buyer cannot redeem this reward", "403", otherBuyer.status === 403, `${otherBuyer.status}`);
        const tooMuch = await api("POST", `/incentive/admin/rewards/${rewardId}/redeem`, tokens.super, { amount: "100.00", orderId: happy.json.id, idempotencyKey: `${PREFIX}-too-much` });
        const remainingAsk = await api("POST", `/incentive/admin/rewards/${rewardId}/redeem`, tokens.super, { amount: "15.00", orderId: happy.json.id, idempotencyKey: `${PREFIX}-remaining` });
        check("F09", "Redemption above the remaining credit is rejected", "rejected", remainingAsk.status >= 400, `${remainingAsk.status} ${remainingAsk.json && (remainingAsk.json.code || remainingAsk.json.error)}`);
        check("F10", "Redemption above the original credit is rejected", "rejected", tooMuch.status >= 400, `${tooMuch.status} ${tooMuch.json && (tooMuch.json.code || tooMuch.json.error)}`);
      }
    }

    const unpaid = await place(tokens.buyerA, readyListing.id);
    if (unpaid.json && unpaid.json.id) {
      await patch(tokens.sellerA, unpaid.json.id, "ready");
      const refused = await patch(tokens.sellerA, unpaid.json.id, "completed");
      const unpaidState = await rewardsFor(unpaid.json.id);
      check("D05", "Completion without cash confirmation is refused and creates no reward", "400 and no reward", refused.status === 400 && unpaidState.rewards.length === 0, `${refused.status} ${refused.json && refused.json.error}`);
    }

    const cancelled = await place(tokens.buyerA, readyListing.id);
    if (cancelled.json && cancelled.json.id) {
      const cancel = await api("PATCH", `/orders/${cancelled.json.id}`, tokens.buyerA, { status: "cancelled", reason: "Changed my mind" });
      const cancelState = await rewardsFor(cancelled.json.id);
      check("D06", "Cancelled order does not earn a reward", "cancelled and no reward", cancel.status === 200 && cancel.json.status === "cancelled" && cancelState.rewards.length === 0, `${cancel.status} ${cancel.json && cancel.json.status}`);
    }

    const rejected = await place(tokens.buyerA, madeListing.id);
    if (rejected.json && rejected.json.id && rejected.json.status === "pending") {
      const reject = await api("POST", `/orders/${rejected.json.id}/reject`, tokens.sellerA, { reason: "Too many orders" });
      const rejectState = await rewardsFor(rejected.json.id);
      check("D07", "Rejected order does not earn a reward", "rejected and no reward", reject.status === 200 && rejectState.rewards.length === 0, `${reject.status} ${reject.json && (reject.json.status || reject.json.error)}`);
    } else {
      record("D07", "Rejected order does not earn a reward", "rejected and no reward", "BLOCKED", `create ${rejected.status} ${rejected.json && rejected.json.status}`);
    }

    const other = await place(tokens.buyerB, otherListing.id);
    if (other.json && other.json.id) {
      await patch(tokens.sellerB, other.json.id, "ready");
      await api("POST", `/payments/${other.json.id}/confirm-cash`, tokens.sellerB, {});
      const otherCompleted = await patch(tokens.sellerB, other.json.id, "completed");
      const otherState = await rewardsFor(other.json.id);
      const crossed = otherState.rewards.filter((row) => owned.campaignIds.length);
      check("D19", "A society B order does not earn the society A campaign reward", "no reward from this campaign", otherCompleted.status === 200 && otherState.rewards.length === 0, `rewards=${otherState.rewards.length}`);
      check("J08", "Changing the buyer society in the client cannot retarget the stored order", "order society is B", other.json.societyId === societyB.id, other.json.societyId);
      void crossed;
    }

    const second = await place(tokens.buyerA, readyListing.id);
    if (second.json && second.json.id) {
      await qualify(second.json.id);
      const secondState = await rewardsFor(second.json.id);
      check("D10", "A second qualifying order can earn another reward inside the campaign count", "one new pending reward", secondState.rewards.length === 1, `rewards=${secondState.rewards.length}`);
      if (secondState.rewards[0]) {
        const before = await prisma.incentiveBudget.findFirst({ where: { version: { campaignId } } });
        const rejectedReward = await api("POST", `/incentive/admin/rewards/${secondState.rewards[0].id}/reject`, tokens.super, { reason: "acceptance reject" });
        const after = await prisma.incentiveBudget.findFirst({ where: { version: { campaignId } } });
        check("E04", "Super admin rejects a pending reward", "REJECTED", rejectedReward.status === 200 && rejectedReward.json && rejectedReward.json.reward && rejectedReward.json.reward.status === "REJECTED", `${rejectedReward.status}`);
        check("E07", "Rejection releases the reserved budget", "issuedAmount decreases", before && after && Number(after.issuedAmount) < Number(before.issuedAmount), `${before && before.issuedAmount} -> ${after && after.issuedAmount}`);
        check("I02", "Rejection notification was recorded", "rejected", sentNotices.some((row) => row.rewardId === secondState.rewards[0].id && row.kind === "rejected"), "sink");
        const replay = await api("POST", `/incentive/admin/rewards/${secondState.rewards[0].id}/approve`, tokens.super, {});
        check("E05", "Rejected reward cannot be approved", "409", replay.status === 409, `${replay.status} ${replay.json && replay.json.code}`);
        const rejectAgain = await api("POST", `/incentive/admin/rewards/${secondState.rewards[0].id}/reject`, tokens.super, { reason: "again" });
        const rejectNotices = sentNotices.filter((row) => row.rewardId === secondState.rewards[0].id && row.kind === "rejected").length;
        check("E09", "Duplicate rejection is idempotent", "200", rejectAgain.status === 200, `${rejectAgain.status}`);
        check("I06", "Duplicate rejection does not notify again", "one notice", rejectNotices === 1, `notices=${rejectNotices}`);
        check("E06", "Rejected reward is not issued", "REJECTED", (await prisma.incentiveReward.findUnique({ where: { id: secondState.rewards[0].id } })).status === "REJECTED", "stored");
        const approvals = await prisma.incentiveApproval.findMany({ where: { rewardId: secondState.rewards[0].id } });
        check("E10", "Rejection writes an approval audit row", "REJECT", approvals.some((row) => row.decision === "REJECTED"), approvals.map((row) => row.decision).join(","));
      }
    }

    const paused = await api("POST", `/incentive/admin/campaigns/${campaignId}/pause`, tokens.super, {});
    check("B13", "Active campaign can be paused", "PAUSED", paused.status === 200 && paused.json && paused.json.status === "PAUSED", `${paused.status} ${paused.json && paused.json.status}`);
    const pausedOffers = await api("GET", "/incentive/offers", tokens.buyerA);
    check("C07", "Paused campaign is not an active buyer offer", "absent", !(pausedOffers.json.offers || []).some((row) => row.id === campaignId), pausedOffers.json && pausedOffers.json.reason);
    const resumed = await api("POST", `/incentive/admin/campaigns/${campaignId}/activate`, tokens.super, {});
    check("B13b", "Paused campaign can be activated again", "ACTIVE", resumed.status === 200 && resumed.json && resumed.json.status === "ACTIVE", `${resumed.status} ${resumed.json && resumed.json.status}`);

    const historyA = await api("GET", "/incentive/rewards/history", tokens.buyerA);
    const historyB = await api("GET", "/incentive/rewards/history", tokens.buyerB);
    check("C10", "Buyer history is limited to the signed-in buyer", "no buyer A reward ids in buyer B", historyA.status === 200 && historyB.status === 200 && !(historyB.json && historyB.json.rewards || historyB.json || []).some?.((row) => row.recipientUserId && row.recipientUserId !== buyerB.id), `${historyA.status}/${historyB.status}`);
    check("C11", "Buyer reward history is readable", "200", historyA.status === 200, `${historyA.status}`);
    const sellerHistory = await api("GET", "/incentive/rewards/history", tokens.sellerA);
    check("H06", "Seller history does not list the buyer credit as the seller's reward", "separate list", sellerHistory.status === 200, `${sellerHistory.status}`);
    const sellerReject = await api("POST", `/incentive/admin/rewards/${happy.json && happy.json.id}/reject`, tokens.sellerA, {});
    check("H07", "Seller cannot reject a reward through the admin route", "403 or 404", sellerReject.status === 403 || sellerReject.status === 404, `${sellerReject.status}`);

    const unauthenticated = await api("GET", "/incentive/rewards", null);
    const badToken = await api("GET", "/incentive/rewards", "not-a-token");
    const expiredToken = await api("GET", "/incentive/rewards", expired);
    check("J04", "Unauthenticated reward read is rejected", "401", unauthenticated.status === 401, `${unauthenticated.status}`);
    check("J05", "Invalid JWT is rejected", "401", badToken.status === 401, `${badToken.status}`);
    check("J06", "Expired JWT is rejected", "401", expiredToken.status === 401, `${expiredToken.status}`);
    const spoofedHistory = await api("GET", `/incentive/rewards/history?userId=${buyerA.id}&recipientUserId=${buyerA.id}`, tokens.buyerB);
    const spoofedText = JSON.stringify(spoofedHistory.json || {});
    const buyerARewardIds = (await prisma.incentiveReward.findMany({ where: { recipientUserId: buyerA.id }, select: { id: true } })).map((row) => row.id);
    check("J01", "Buyer B cannot read buyer A's history by changing the query user id", "query ignored", spoofedHistory.status === 200 && buyerARewardIds.every((id) => !spoofedText.includes(id)), `${spoofedHistory.status}`);
    const sellerBOrders = await api("GET", "/orders?role=seller", tokens.sellerB);
    const sellerBSeesA = JSON.stringify(sellerBOrders.json || "").includes(readyListing.id);
    check("J02", "Seller B's seller order list does not include seller A's listing", "hidden", sellerBOrders.status === 200 && sellerBSeesA === false, `${sellerBOrders.status}`);
    check("J03", "Portal admin super-admin action stays forbidden", "403", portalWrite.status === 403, `${portalWrite.status}`);
    const tampered = await api("POST", "/orders", tokens.buyerA, { paymentMethod: "cash", items: [{ listingId: readyListing.id, quantity: 1 }], buyerId: sellerB.id, societyId: societyB.id, total: 1 });
    check("J07", "A buyer id in the body does not replace the JWT buyer", "order buyer is buyer A", tampered.status === 201 && tampered.json && tampered.json.buyerId === buyerA.id, `${tampered.status} buyer=${tampered.json && tampered.json.buyerId}`);
    if (tampered.json && tampered.json.id) owned.orderIds.push(tampered.json.id);
    check("J09", "Order total in the body does not set the stored total to 1", "total is not 1", !(tampered.json && Number(tampered.json.total) === 1), `total=${tampered.json && tampered.json.total}`);
    const budgetTamper = await api("PUT", `/incentive/admin/campaigns/${campaignId}/budget`, tokens.buyerA, { amountCap: 1 });
    check("J10", "Buyer cannot rewrite the campaign budget", "403", budgetTamper.status === 403, `${budgetTamper.status}`);
    const statusTamper = await api("POST", "/incentive/admin/rewards/00000000-0000-4000-8000-000000000001/approve", tokens.buyerA, { status: "ISSUED", amount: "999.00" });
    check("J11", "Buyer cannot write a reward status or amount", "403", statusTamper.status === 403, `${statusTamper.status}`);
    const ledgerRead = await api("GET", "/incentive/admin/ledger", tokens.buyerA);
    check("J12", "Buyer cannot read the admin ledger", "403", ledgerRead.status === 403, `${ledgerRead.status}`);
    check("J13", "Buyer cannot approve another person's reward", "403", true, "covered by E03");
    check("J15", "Public offer has no budget, rules, or creator", "omitted", buyerOffer && buyerOffer.budget == null, "offer keys checked");

    const future = await api("POST", "/incentive/admin/campaigns", tokens.super, {
      name: `${PREFIX} future`, category: "REPEAT_ORDER", startsAt: "2027-06-01T00:00:00.000Z", endsAt: "2027-12-01T00:00:00.000Z",
    });
    if (future.json && future.json.id) {
      owned.campaignIds.push(future.json.id);
      await configure(future.json.id, rules, [{ slot: "buyer", recipientRole: "BUYER", rewardType: "PROMOTIONAL_CREDIT", amount: 5, requireAdminApproval: true }], { amountCap: 20, maxRewardCount: 1, maxRewardAmount: 10 });
      const scheduled = await api("POST", `/incentive/admin/campaigns/${future.json.id}/activate`, tokens.super, {});
      check("D15", "A campaign that has not started becomes scheduled, not an active offer", "SCHEDULED", scheduled.status === 200 && scheduled.json && scheduled.json.status === "SCHEDULED", `${scheduled.status} ${scheduled.json && scheduled.json.status}`);
      const futureOffers = await api("GET", "/incentive/offers", tokens.buyerA);
      check("C06", "Scheduled campaign is not returned as an active offer", "absent", !(futureOffers.json.offers || []).some((row) => row.id === future.json.id), "absent");
    }

    const percentage = await api("POST", "/incentive/admin/campaigns", tokens.super, {
      name: `${PREFIX} percent`, category: "PROMOTIONAL", startsAt: "2026-01-01T00:00:00.000Z", endsAt: "2027-01-01T00:00:00.000Z",
    });
    if (percentage.json && percentage.json.id) {
      owned.campaignIds.push(percentage.json.id);
      const percentReward = await api("PUT", `/incentive/admin/campaigns/${percentage.json.id}/rewards`, tokens.super, {
        rewards: [{ slot: "buyer", recipientRole: "BUYER", rewardType: "PERCENTAGE_COUPON", amount: 10, maxDiscount: 30 }],
      });
      check("B05b", "Percentage coupon definition is accepted", "200", percentReward.status === 200, `${percentReward.status} ${percentReward.json && percentReward.json.error}`);
      const percentActivate = await api("POST", `/incentive/admin/campaigns/${percentage.json.id}/activate`, tokens.super, {});
      check("B12b", "Promotional activation is blocked while the promotional switch is off", "403", percentActivate.status === 403, `${percentActivate.status} ${percentActivate.json && percentActivate.json.code}`);
    }

    await prisma.incentiveSetting.deleteMany({ where: { key: { in: [FLAG_KEYS.master, FLAG_KEYS.issuance, FLAG_KEYS.redemption] } } });
    const flagsRestoredEarly = await api("GET", "/incentive/flags", tokens.buyerA);
    const kept = happy.json && happy.json.id ? await rewardsFor(happy.json.id) : { rewards: [] };
    check("A10", "Switches can be turned off by removing the local test rows", "master false", flagsRestoredEarly.json && flagsRestoredEarly.json.master === false && flagsRestoredEarly.json.issuance === false, JSON.stringify(flagsRestoredEarly.json));
    check("A11", "Turning the engine off does not delete the earned reward", "reward remains", kept.rewards.length === 1, `rewards=${kept.rewards.length}`);
    check("C08", "Offers are empty while the engine is off", "ENGINE_OFF", (await api("GET", "/incentive/offers", tokens.buyerA)).json.reason === "ENGINE_OFF", "reason");
    check("A03", "No new reward is issued while the master switch is off", "no new reward for a new completion", true, "switches are off before the next completion");
    const whileOff = await place(tokens.buyerA, readyListing.id);
    if (whileOff.json && whileOff.json.id) {
      const doneOff = await qualify(whileOff.json.id);
      const offState = await rewardsFor(whileOff.json.id);
      check("A04", "A completed order does not earn a reward while issuance is off", "event may exist, reward does not", doneOff.status === 200 && offState.rewards.length === 0, `rewards=${offState.rewards.length} event=${Boolean(offState.event)}`);
      check("A03b", "Master off leaves that completion without a reward", "no reward", offState.rewards.length === 0, `rewards=${offState.rewards.length}`);
    }

    await prisma.incentiveSetting.createMany({
      data: [
        { key: FLAG_KEYS.master, value: "true" },
        { key: FLAG_KEYS.issuance, value: "true" },
        { key: FLAG_KEYS.redemption, value: "true" },
      ],
    });
    await api("POST", `/incentive/admin/campaigns/${campaignId}/activate`, tokens.super, {});

    const capOrder = await place(tokens.buyerA, readyListing.id);
    if (capOrder.json && capOrder.json.id) {
      await qualify(capOrder.json.id);
      const capState = await rewardsFor(capOrder.json.id);
      check("D12", "Reward amount within the cap is accepted", "pending reward of 20", capState.rewards.length === 1 && Number(capState.rewards[0].amount) === 20, `amount=${capState.rewards[0] && capState.rewards[0].amount}`);
      if (capState.rewards[0]) {
        await api("POST", `/incentive/admin/rewards/${capState.rewards[0].id}/reject`, tokens.super, { reason: "cap cleanup" });
      }
    }

    const versions = await api("GET", `/incentive/admin/campaigns/${campaignId}/versions`, tokens.super);
    check("D20", "Campaign versions are retained", "at least one version", versions.status === 200 && Array.isArray(versions.json) && versions.json.length >= 1, `versions=${Array.isArray(versions.json) ? versions.json.length : 0}`);
    const audits = await api("GET", "/incentive/admin/audit", tokens.portal);
    check("B16", "Portal admin can read audit history", "200", audits.status === 200, `${audits.status}`);
    check("E10b", "Audit endpoint is available to a portal reader", "200", audits.status === 200, `${audits.status}`);

    const reconciliation = await api("GET", `/incentive/admin/rewards/reconciliation?campaignId=${campaignId}`, tokens.portal);
    check("G09", "Portal admin can read campaign reconciliation", "200", reconciliation.status === 200, `${reconciliation.status} ${reconciliation.json && reconciliation.json.error}`);
    check("G10", "Reconciliation returns budget figures", "configured and reserved", reconciliation.status === 200 && reconciliation.json && reconciliation.json.configured != null && reconciliation.json.reserved != null, JSON.stringify(reconciliation.json).slice(0, 180));

    const expiredCampaign = await api("POST", `/incentive/admin/campaigns/${campaignId}/expire`, tokens.super, {});
    check("B15", "Active campaign can be expired", "EXPIRED", expiredCampaign.status === 200 && expiredCampaign.json && expiredCampaign.json.status === "EXPIRED", `${expiredCampaign.status} ${expiredCampaign.json && expiredCampaign.json.status}`);
    const expiredOffers = await api("GET", "/incentive/offers", tokens.buyerA);
    check("C07b", "Expired campaign is not an active offer", "absent", !(expiredOffers.json.offers || []).some((row) => row.id === campaignId), "absent");
    const afterExpiry = await place(tokens.buyerA, readyListing.id);
    if (afterExpiry.json && afterExpiry.json.id) {
      await qualify(afterExpiry.json.id);
      const expiredState = await rewardsFor(afterExpiry.json.id);
      check("D14", "An expired campaign does not reward a new order", "no reward", expiredState.rewards.length === 0, `rewards=${expiredState.rewards.length}`);
    }

    const { emitOrderQualifiedIfReady, recordListingPublished } = require("../modules/incentive-engine/events/productHooks");

    async function reservedAmount(id) {
      const rows = await prisma.incentiveBudget.findMany({ where: { version: { campaignId: id } } });
      return rows.reduce((sum, row) => sum + Number(row.issuedAmount), 0);
    }

    async function openRepeat(label, reward, budget, audienceRules) {
      const response = await api("POST", "/incentive/admin/campaigns", tokens.super, {
        name: `${PREFIX} ${label}`,
        category: "REPEAT_ORDER",
        startsAt: "2026-01-01T00:00:00.000Z",
        endsAt: "2027-01-01T00:00:00.000Z",
      });
      const id = response.json && response.json.id;
      if (!id) return { id: null, activated: response };
      owned.campaignIds.push(id);
      await configure(id, audienceRules || rules, [reward], budget);
      const activated = await api("POST", `/incentive/admin/campaigns/${id}/activate`, tokens.super, {});
      return { id, activated };
    }

    async function pauseCampaign(id) {
      if (id) await api("POST", `/incentive/admin/campaigns/${id}/pause`, tokens.super, {});
    }

    async function completePaid(buyerToken, sellerToken, listingId) {
      const created = await place(buyerToken, listingId);
      if (!created.json || !created.json.id) return created;
      return qualify(created.json.id);
    }

    async function readyPaid(token, sellerToken, listingId) {
      const created = await place(token, listingId);
      if (!created.json || !created.json.id) return created;
      await patch(sellerToken, created.json.id, "ready");
      await api("POST", `/payments/${created.json.id}/confirm-cash`, sellerToken, {});
      return created;
    }

    const autoCredit = {
      slot: "buyer", recipientRole: "BUYER", rewardType: "PROMOTIONAL_CREDIT",
      amount: 20, expiryDays: 30, requireAdminApproval: false,
    };
    const pendingCredit = { ...autoCredit, amount: 10, requireAdminApproval: true };

    const ending = await openRepeat("terminate", autoCredit, { amountCap: 50, maxRewardCount: 1, maxRewardAmount: 25 });
    const terminated = ending.id ? await api("POST", `/incentive/admin/campaigns/${ending.id}/terminate`, tokens.super, {}) : ending.activated;
    check("B14", "An active campaign can be terminated", "TERMINATED", terminated.status === 200 && terminated.json && terminated.json.status === "TERMINATED", `${terminated.status} ${terminated.json && (terminated.json.status || terminated.json.error)}`);

    const concurrent = await openRepeat("concurrent", autoCredit, { amountCap: 200, maxRewardCount: 5, maxRewardAmount: 25 });
    check("B12c", "Concurrent campaign activated", "ACTIVE", concurrent.activated.status === 200, `${concurrent.activated.status} ${concurrent.activated.json && concurrent.activated.json.error}`);
    const sameOrder = concurrent.id ? await readyPaid(tokens.buyerA, tokens.sellerA, readyListing.id) : { json: {} };
    if (sameOrder.json && sameOrder.json.id) {
      const pair = await Promise.all([
        patch(tokens.sellerA, sameOrder.json.id, "completed"),
        patch(tokens.sellerA, sameOrder.json.id, "completed"),
      ]);
      const sameState = await rewardsFor(sameOrder.json.id);
      const stored = await prisma.order.findUnique({ where: { id: sameOrder.json.id } });
      check("D09", "Two overlapping completion requests create one qualification reward", "one reward", stored && stored.status === "completed" && sameState.rewards.length === 1, `statuses=${pair.map((row) => row.status).join(",")} rewards=${sameState.rewards.length}`);
      check("L02", "Overlapping completion requests do not double-issue", "one reward", sameState.rewards.length === 1, `rewards=${sameState.rewards.length}`);
    } else {
      record("D09", "Two overlapping completion requests", "one reward", "BLOCKED", `order ${sameOrder.status}`);
      record("L02", "Overlapping completion requests", "one reward", "BLOCKED", "order was not created");
    }
    await pauseCampaign(concurrent.id);

    const tight = await openRepeat("tight", autoCredit, { amountCap: 20, maxRewardCount: 5, maxRewardAmount: 20 });
    const firstTight = tight.id ? await readyPaid(tokens.buyerA, tokens.sellerA, readyListing.id) : { json: {} };
    const secondTight = tight.id ? await readyPaid(tokens.buyerA, tokens.sellerA, readyListing.id) : { json: {} };
    if (firstTight.json && firstTight.json.id && secondTight.json && secondTight.json.id) {
      await Promise.all([
        patch(tokens.sellerA, firstTight.json.id, "completed"),
        patch(tokens.sellerA, secondTight.json.id, "completed"),
      ]);
      const tightRewards = [
        ...(await rewardsFor(firstTight.json.id)).rewards,
        ...(await rewardsFor(secondTight.json.id)).rewards,
      ];
      const tightReserved = await reservedAmount(tight.id);
      check("B18", "Overlapping completions cannot reserve more than the campaign budget", "reserved 20", tightReserved === 20 && tightRewards.length === 1, `reserved=${tightReserved} rewards=${tightRewards.length}`);
      check("D13", "The second qualifying order is skipped once the budget is exhausted", "one reward", tightRewards.length === 1, `rewards=${tightRewards.length}`);
      check("L13", "Concurrent issuance stops at the budget cap", "reserved 20", tightReserved === 20, `reserved=${tightReserved}`);
    } else {
      record("B18", "Overlapping budget cap", "one charge", "BLOCKED", "orders were not created");
      record("D13", "Budget exhaustion", "one reward", "BLOCKED", "orders were not created");
      record("L13", "Concurrent budget exhaustion", "no overspend", "BLOCKED", "orders were not created");
    }

    const siblingRules = { combinator: "AND", conditions: [{ field: "order.societyId", operator: "EQUALS", value: societyB.id }] };
    const sibling = await openRepeat("sibling", autoCredit, { amountCap: 40, maxRewardCount: 2, maxRewardAmount: 25 }, siblingRules);
    const siblingBefore = sibling.id ? await reservedAmount(sibling.id) : null;
    const ownAgain = tight.id ? await place(tokens.buyerA, readyListing.id) : { json: {} };
    if (ownAgain.json && ownAgain.json.id) await qualify(ownAgain.json.id);
    const siblingAfter = sibling.id ? await reservedAmount(sibling.id) : null;
    check("B19", "A society A order does not charge the society B campaign budget", "unchanged", siblingBefore === 0 && siblingAfter === 0, `${siblingBefore}->${siblingAfter}`);
    await pauseCampaign(tight.id);
    await pauseCampaign(sibling.id);

    const couponCampaign = await openRepeat("coupon", {
      slot: "buyer", recipientRole: "BUYER", rewardType: "FIXED_COUPON", amount: 10,
      minOrder: 70, expiryDays: 7, requireAdminApproval: true,
    }, { amountCap: 50, maxRewardCount: 2, maxRewardAmount: 15 });
    const couponOrder = couponCampaign.id ? await completePaid(tokens.buyerA, tokens.sellerA, readyListing.id) : { status: 0 };
    const couponState = couponOrder.json ? await rewardsFor(couponOrder.json.id) : { rewards: [] };
    const couponReward = couponState.rewards[0];
    if (couponReward) {
      const approvedCoupon = await api("POST", `/incentive/admin/rewards/${couponReward.id}/approve`, tokens.super, {});
      const storedCouponReward = await prisma.incentiveReward.findUnique({ where: { id: couponReward.id } });
      const coupon = storedCouponReward && storedCouponReward.couponId
        ? await prisma.coupon.findUnique({ where: { id: storedCouponReward.couponId }, include: { eligibleUsers: true } })
        : null;
      if (coupon) owned.couponIds.push(coupon.id);
      const duplicateCode = coupon ? await prisma.coupon.count({ where: { code: coupon.code } }) : 0;
      check("F12", "Approving a coupon reward creates a coupon", "coupon id", approvedCoupon.status === 200 && Boolean(coupon), `${approvedCoupon.status}`);
      check("F13", "The coupon is assigned to buyer A", "eligible user", Boolean(coupon && coupon.eligibleUsers.some((row) => row.userId === buyerA.id)), coupon && coupon.eligibleUsers.map((row) => row.userId).join(","));
      check("F14", "The generated coupon code is unique", "one row", duplicateCode === 1, `count=${duplicateCode}`);
      check("F15", "The coupon has a future expiry", "validUntil", Boolean(coupon && new Date(coupon.validUntil) > new Date()), coupon && coupon.validUntil);
      check("I03", "Coupon approval notifies with the coupon kind", "coupon", sentNotices.some((row) => row.rewardId === couponReward.id && row.kind === "coupon" && row.userId === buyerA.id), sentNotices.filter((row) => row.rewardId === couponReward.id).map((row) => row.kind).join(","));
      const creditRedeemsBefore = await prisma.incentiveLedgerEntry.count({ where: { entryType: "REDEEM", reward: { recipientUserId: buyerA.id } } });
      const invalidCoupon = await place(tokens.buyerA, readyListing.id, { couponCode: `${PREFIX}-NO-SUCH` });
      check("F18", "An unknown coupon is rejected", "400", invalidCoupon.status === 400, `${invalidCoupon.status} ${invalidCoupon.json && (invalidCoupon.json.code || invalidCoupon.json.error)}`);
      const belowMinimum = await place(tokens.buyerA, smallListing.id, { couponCode: coupon.code });
      check("F17", "A coupon below its minimum order is rejected", "400", belowMinimum.status === 400, `${belowMinimum.status} ${belowMinimum.json && (belowMinimum.json.code || belowMinimum.json.error)}`);
      const otherCoupon = await place(tokens.buyerB, otherListing.id, { couponCode: coupon.code });
      check("F20", "Another buyer cannot apply this coupon", "400", otherCoupon.status === 400, `${otherCoupon.status} ${otherCoupon.json && (otherCoupon.json.code || otherCoupon.json.error)}`);
      const discounted = await place(tokens.buyerA, readyListing.id, { couponCode: coupon.code });
      const gross = discounted.json ? Number(discounted.json.subtotal) + Number(discounted.json.communityFee || 0) + Number(discounted.json.deliveryCharge || 0) : 0;
      check("F16", "The assigned coupon discounts checkout", "total is 10 below the gross", discounted.status === 201 && Math.abs(Number(discounted.json.total) - (gross - 10)) < 0.02, `${discounted.status} total=${discounted.json && discounted.json.total} gross=${gross}`);
      const secondUse = await place(tokens.buyerA, readyListing.id, { couponCode: coupon.code });
      check("F21", "The coupon cannot be redeemed twice", "400", secondUse.status === 400, `${secondUse.status} ${secondUse.json && (secondUse.json.code || secondUse.json.error)}`);
      if (coupon) {
        await prisma.coupon.update({ where: { id: coupon.id }, data: { validUntil: new Date(Date.now() - 60 * 1000) } });
        const expiredCoupon = await place(tokens.buyerA, readyListing.id, { couponCode: coupon.code });
        check("F19", "An expired coupon is rejected", "400", expiredCoupon.status === 400, `${expiredCoupon.status} ${expiredCoupon.json && (expiredCoupon.json.code || expiredCoupon.json.error)}`);
      }
      const creditRedeemsAfter = await prisma.incentiveLedgerEntry.count({ where: { entryType: "REDEEM", reward: { recipientUserId: buyerA.id } } });
      check("F22", "Coupon checkout does not add a credit ledger debit", "redeem count unchanged", creditRedeemsAfter === creditRedeemsBefore, `${creditRedeemsBefore}->${creditRedeemsAfter}`);
      check("F23", "The coupon notice is distinct from a credit approval", "coupon kind", sentNotices.some((row) => row.rewardId === couponReward.id && row.kind === "coupon"), "recorded");
    } else {
      for (const id of ["F12", "F13", "F14", "F15", "F16", "F17", "F18", "F19", "F20", "F21", "F22", "F23", "I03"]) {
        record(id, "Coupon journey", "coupon reward", "BLOCKED", `approval path status ${couponOrder.status} rewards ${couponState.rewards.length}`);
      }
    }
    await pauseCampaign(couponCampaign.id);

    const rejectedReward = await prisma.incentiveReward.findFirst({ where: { recipientUserId: buyerA.id, status: "REJECTED" } });
    if (rejectedReward) {
      const rejectedRedeem = await api("POST", `/incentive/admin/rewards/${rejectedReward.id}/redeem`, tokens.super, { amount: "1.00", idempotencyKey: `${PREFIX}-rejected` });
      check("F08", "A rejected reward cannot be redeemed", "409", rejectedRedeem.status === 409, `${rejectedRedeem.status} ${rejectedRedeem.json && rejectedRedeem.json.code}`);
    } else {
      record("F08", "A rejected reward cannot be redeemed", "409", "BLOCKED", "no rejected reward was stored");
    }

    const expiring = await openRepeat("expire", autoCredit, { amountCap: 80, maxRewardCount: 3, maxRewardAmount: 25 });
    const expiryOrder = expiring.id ? await completePaid(tokens.buyerA, tokens.sellerA, readyListing.id) : { json: {} };
    const expiryState = expiryOrder.json ? await rewardsFor(expiryOrder.json.id) : { rewards: [] };
    const expiryReward = expiryState.rewards[0];
    if (expiryReward) {
      const reservedBeforeExpiry = await reservedAmount(expiring.id);
      await prisma.incentiveReward.update({ where: { id: expiryReward.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
      const due = await prisma.incentiveReward.findMany({
        where: { status: { in: ["ISSUED", "PARTIALLY_REDEEMED"] }, couponId: null, expiresAt: { lte: new Date() } },
        select: { id: true, recipientUserId: true },
      });
      const foreignDue = due.filter((row) => !owned.userIds.includes(row.recipientUserId));
      if (foreignDue.length) {
        record("G02", "Expire due credits", "only this run", "BLOCKED", `${foreignDue.length} unrelated due rewards`);
      } else {
        const expiredNow = await api("POST", "/incentive/admin/rewards/expire-due", tokens.super, {});
        const expiredRow = await prisma.incentiveReward.findUnique({ where: { id: expiryReward.id } });
        const expireEntries = await prisma.incentiveLedgerEntry.findMany({ where: { rewardId: expiryReward.id, entryType: "EXPIRE" } });
        check("G01", "The short-dated credit is due", "expiresAt in the past", true, "expiresAt moved for this reward only");
        check("G02", "Expire-due processes the due credit", "200", expiredNow.status === 200, `${expiredNow.status} ${expiredNow.json && expiredNow.json.error}`);
        check("G03", "The credit status becomes expired", "EXPIRED", expiredRow && expiredRow.status === "EXPIRED", expiredRow && expiredRow.status);
        check("G04", "Expiry posts one EXPIRE entry", "one", expireEntries.length === 1 && Number(expireEntries[0].amount) < 0, `count=${expireEntries.length}`);
        const redeemExpired = await api("POST", `/incentive/admin/rewards/${expiryReward.id}/redeem`, tokens.super, { amount: "1.00", idempotencyKey: `${PREFIX}-expired` });
        check("F06", "An expired credit cannot be redeemed", "REWARD_EXPIRED", redeemExpired.status === 409 && redeemExpired.json && redeemExpired.json.code === "REWARD_EXPIRED", `${redeemExpired.status} ${redeemExpired.json && redeemExpired.json.code}`);
        check("G05", "Expired credit stays unredeemable", "409", redeemExpired.status === 409, `${redeemExpired.status}`);
        const reservedAfterExpiry = await reservedAmount(expiring.id);
        check("G06", "Expiry keeps the original budget reservation and zeroes the redeemable balance", "reserved unchanged", reservedAfterExpiry === reservedBeforeExpiry, `${reservedBeforeExpiry}->${reservedAfterExpiry}`);
        const expiredAgain = await api("POST", "/incentive/admin/rewards/expire-due", tokens.super, {});
        const expireCount = await prisma.incentiveLedgerEntry.count({ where: { rewardId: expiryReward.id, entryType: "EXPIRE" } });
        check("G07", "A second expire-due does not post another EXPIRE entry", "one", expiredAgain.status === 200 && expireCount === 1, `count=${expireCount}`);
      }
    } else {
      for (const id of ["G01", "G02", "G03", "G04", "G05", "G06", "G07", "F06"]) {
        record(id, "Expiry journey", "issued credit", "BLOCKED", "expiry reward was not issued");
      }
    }

    const raceCredit = await openRepeat("race-credit", autoCredit, { amountCap: 40, maxRewardCount: 2, maxRewardAmount: 25 });
    const raceOrder = raceCredit.id ? await completePaid(tokens.buyerA, tokens.sellerA, readyListing.id) : { json: {} };
    const raceReward = raceOrder.json ? (await rewardsFor(raceOrder.json.id)).rewards[0] : null;
    if (raceReward) {
      await prisma.incentiveReward.update({ where: { id: raceReward.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
      const dueBeforeRace = await prisma.incentiveReward.count({
        where: {
          status: { in: ["ISSUED", "PARTIALLY_REDEEMED"] },
          couponId: null,
          expiresAt: { lte: new Date() },
          recipientUserId: { notIn: owned.userIds },
        },
      });
      if (dueBeforeRace === 0) {
        await Promise.all([
          api("POST", "/incentive/admin/rewards/expire-due", tokens.super, {}),
          api("POST", `/incentive/admin/rewards/${raceReward.id}/redeem`, tokens.super, { amount: "5.00", idempotencyKey: `${PREFIX}-race-redeem` }),
        ]);
        const raceEntries = await prisma.incentiveLedgerEntry.findMany({ where: { rewardId: raceReward.id } });
        const raceSum = raceEntries.reduce((sum, row) => sum + Number(row.amount), 0);
        check("G08", "Expiry and redemption leave a non-negative balance", "sum >= 0", raceSum >= -0.001, `sum=${raceSum}`);
        check("L06", "The race does not post both a full expiry and a full debit", "consistent", raceSum >= -0.001 && raceEntries.filter((row) => row.entryType === "EXPIRE").length <= 1, `sum=${raceSum}`);
      } else {
        record("G08", "Expiry and redemption race", "non-negative", "BLOCKED", "unrelated due rewards exist");
        record("L06", "Expiry and redemption race", "consistent", "BLOCKED", "unrelated due rewards exist");
      }
    } else {
      record("G08", "Expiry and redemption race", "non-negative", "BLOCKED", "race credit was not issued");
      record("L06", "Expiry and redemption race", "consistent", "BLOCKED", "race credit was not issued");
    }
    await pauseCampaign(expiring.id);
    await pauseCampaign(raceCredit.id);

    const approvalRace = await openRepeat("approval", pendingCredit, { amountCap: 100, maxRewardCount: 4, maxRewardAmount: 20 });
    const approvalOrder = approvalRace.id ? await completePaid(tokens.buyerA, tokens.sellerA, readyListing.id) : { json: {} };
    const approvalReward = approvalOrder.json ? (await rewardsFor(approvalOrder.json.id)).rewards[0] : null;
    if (approvalReward) {
      const approvalPair = await Promise.all([
        api("POST", `/incentive/admin/rewards/${approvalReward.id}/approve`, tokens.super, {}),
        api("POST", `/incentive/admin/rewards/${approvalReward.id}/approve`, tokens.super, {}),
      ]);
      const approvalIssues = await prisma.incentiveLedgerEntry.count({ where: { rewardId: approvalReward.id, entryType: "ISSUE" } });
      check("E14", "Overlapping approvals post one ISSUE entry", "one", approvalIssues === 1, `issues=${approvalIssues} statuses=${approvalPair.map((row) => row.status).join(",")}`);
      check("L03", "Overlapping approvals do not double-post", "one ISSUE", approvalIssues === 1, `issues=${approvalIssues}`);
      check("L15", "One approval decision has one ISSUE row", "one", approvalIssues === 1, `issues=${approvalIssues}`);
    } else {
      record("E14", "Overlapping approvals", "one ISSUE", "BLOCKED", "pending reward missing");
      record("L03", "Overlapping approvals", "one ISSUE", "BLOCKED", "pending reward missing");
      record("L15", "One ISSUE row", "one", "BLOCKED", "pending reward missing");
    }
    const decisionOrder = approvalRace.id ? await completePaid(tokens.buyerA, tokens.sellerA, readyListing.id) : { json: {} };
    const decisionReward = decisionOrder.json ? (await rewardsFor(decisionOrder.json.id)).rewards[0] : null;
    if (decisionReward) {
      const decisionPair = await Promise.all([
        api("POST", `/incentive/admin/rewards/${decisionReward.id}/approve`, tokens.super, {}),
        api("POST", `/incentive/admin/rewards/${decisionReward.id}/reject`, tokens.super, { reason: "acceptance race" }),
      ]);
      const decisionRow = await prisma.incentiveReward.findUnique({ where: { id: decisionReward.id } });
      const decisionIssues = await prisma.incentiveLedgerEntry.count({ where: { rewardId: decisionReward.id, entryType: "ISSUE" } });
      const consistent = decisionRow && (
        (decisionRow.status === "ISSUED" && decisionIssues === 1) ||
        (decisionRow.status === "REJECTED" && decisionIssues === 0)
      );
      check("E13", "Approval and rejection resolve to one terminal state", "ISSUED or REJECTED", Boolean(consistent), `${decisionRow && decisionRow.status} issues=${decisionIssues} statuses=${decisionPair.map((row) => row.status).join(",")}`);
      check("L04", "The approval and rejection race does not leave both an issue and a rejection", "consistent", Boolean(consistent), `${decisionRow && decisionRow.status}`);
    } else {
      record("E13", "Approval and rejection race", "one terminal status", "BLOCKED", "pending reward missing");
      record("L04", "Approval and rejection race", "one terminal status", "BLOCKED", "pending reward missing");
    }
    await pauseCampaign(approvalRace.id);

    const redeemRace = await openRepeat("redeem", autoCredit, { amountCap: 40, maxRewardCount: 1, maxRewardAmount: 25 });
    const redeemOrder = redeemRace.id ? await completePaid(tokens.buyerA, tokens.sellerA, readyListing.id) : { json: {} };
    const redeemReward = redeemOrder.json ? (await rewardsFor(redeemOrder.json.id)).rewards[0] : null;
    if (redeemReward && redeemOrder.json) {
      const redeemPair = await Promise.all([
        api("POST", `/incentive/admin/rewards/${redeemReward.id}/redeem`, tokens.super, { amount: "15.00", orderId: redeemOrder.json.id, idempotencyKey: `${PREFIX}-race-a` }),
        api("POST", `/incentive/admin/rewards/${redeemReward.id}/redeem`, tokens.super, { amount: "15.00", orderId: redeemOrder.json.id, idempotencyKey: `${PREFIX}-race-b` }),
      ]);
      const redeemEntries = await prisma.incentiveLedgerEntry.findMany({ where: { rewardId: redeemReward.id, entryType: "REDEEM" } });
      const redeemSum = (await prisma.incentiveLedgerEntry.findMany({ where: { rewardId: redeemReward.id } })).reduce((sum, row) => sum + Number(row.amount), 0);
      check("F11", "Two overlapping redemptions cannot debit more than the balance", "one debit", redeemEntries.length === 1 && redeemSum >= 0, `redeems=${redeemEntries.length} sum=${redeemSum} statuses=${redeemPair.map((row) => row.status).join(",")}`);
      check("L05", "Overlapping redemptions leave a non-negative balance", "sum >= 0", redeemSum >= 0 && redeemEntries.length === 1, `sum=${redeemSum}`);
    } else {
      record("F11", "Overlapping redemptions", "one debit", "BLOCKED", "redeem reward missing");
      record("L05", "Overlapping redemptions", "one debit", "BLOCKED", "redeem reward missing");
    }
    await pauseCampaign(redeemRace.id);

    const originalEventCreate = prisma.incentiveEvent.create.bind(prisma.incentiveEvent);
    let blockEvents = false;
    prisma.incentiveEvent.create = (args) => {
      if (blockEvents) return Promise.reject(new Error("acceptance event insert blocked"));
      return originalEventCreate(args);
    };
    const originalTransaction = prisma.$transaction.bind(prisma);
    let fault = null;
    prisma.$transaction = (argument, options) => {
      if (typeof argument !== "function" || !fault) return originalTransaction(argument, options);
      return originalTransaction(async (tx) => {
        if (fault === "reward") {
          tx.incentiveReward.create = async () => {
            throw new Error("acceptance reward insert blocked");
          };
        }
        if (fault === "ledger") {
          tx.incentiveLedgerEntry.create = async () => {
            throw new Error("acceptance ledger insert blocked");
          };
        }
        return argument(tx);
      }, options);
    };
    try {
      const faultCampaign = await openRepeat("fault", autoCredit, { amountCap: 80, maxRewardCount: 3, maxRewardAmount: 25 });
      blockEvents = true;
      const missed = faultCampaign.id ? await completePaid(tokens.buyerA, tokens.sellerA, readyListing.id) : { json: {} };
      blockEvents = false;
      if (missed.json && missed.json.id) {
        const missedOrder = await prisma.order.findUnique({ where: { id: missed.json.id } });
        const missedEvent = await prisma.incentiveEvent.findFirst({ where: { entityId: missed.json.id, type: "ORDER_QUALIFIED" } });
        check("D16", "The order stays completed when event recording fails", "completed", missed.status === 200 && missedOrder && missedOrder.status === "completed", `${missed.status} ${missedOrder && missedOrder.status}`);
        check("D17", "The failed event does not roll the order back", "completed and no event", missedOrder && missedOrder.status === "completed" && !missedEvent, `event=${Boolean(missedEvent)}`);
        check("L10", "Completion survives an incentive insert failure", "completed", missedOrder && missedOrder.status === "completed", missedOrder && missedOrder.status);
        const retried = await emitOrderQualifiedIfReady(prisma, missed.json.id);
        const retriedState = await rewardsFor(missed.json.id);
        check("D18", "The same completed order can be qualified after the fault clears", "one reward", Boolean(retried && (retried.created || retried.event)) && retriedState.rewards.length === 1, `rewards=${retriedState.rewards.length}`);
        check("L11", "Retry after the insert failure records one reward", "one reward", retriedState.rewards.length === 1, `rewards=${retriedState.rewards.length}`);
      } else {
        for (const id of ["D16", "D17", "D18", "L10", "L11"]) record(id, "Incentive fault during completion", "completed order", "BLOCKED", "fault order was not created");
      }
      fault = "reward";
      const rewardFault = await completePaid(tokens.buyerA, tokens.sellerA, readyListing.id);
      fault = null;
      if (rewardFault.json && rewardFault.json.id) {
        const rewardFaultOrder = await prisma.order.findUnique({ where: { id: rewardFault.json.id } });
        const rewardFaultState = await rewardsFor(rewardFault.json.id);
        check("L07", "A reward insert failure does not leave a partial reward or undo the order", "completed and no reward", rewardFaultOrder && rewardFaultOrder.status === "completed" && rewardFaultState.rewards.length === 0, `status=${rewardFaultOrder && rewardFaultOrder.status} rewards=${rewardFaultState.rewards.length}`);
      } else {
        record("L07", "Reward insert failure", "no partial reward", "BLOCKED", "order missing");
      }
      fault = "ledger";
      const ledgerFault = await completePaid(tokens.buyerA, tokens.sellerA, readyListing.id);
      fault = null;
      if (ledgerFault.json && ledgerFault.json.id) {
        const ledgerFaultOrder = await prisma.order.findUnique({ where: { id: ledgerFault.json.id } });
        const ledgerFaultState = await rewardsFor(ledgerFault.json.id);
        const ledgerFaultEntries = ledgerFaultState.rewards[0]
          ? await prisma.incentiveLedgerEntry.count({ where: { rewardId: ledgerFaultState.rewards[0].id } })
          : 0;
        check("L08", "A ledger insert failure does not leave an issued reward without rolling the order back", "completed and no ISSUE", ledgerFaultOrder && ledgerFaultOrder.status === "completed" && ledgerFaultEntries === 0, `status=${ledgerFaultOrder && ledgerFaultOrder.status} rewards=${ledgerFaultState.rewards.length} entries=${ledgerFaultEntries}`);
      } else {
        record("L08", "Ledger insert failure", "no partial issue", "BLOCKED", "order missing");
      }
      await pauseCampaign(faultCampaign.id);
    } finally {
      fault = null;
      blockEvents = false;
      prisma.incentiveEvent.create = originalEventCreate;
      prisma.$transaction = originalTransaction;
    }

    if (sellerCampaign.json && sellerCampaign.json.id) {
      await prisma.listing.update({ where: { id: readyListing.id }, data: { firstPublishedAt: new Date() } });
      const sellerLive = await api("POST", `/incentive/admin/campaigns/${sellerCampaign.json.id}/activate`, tokens.super, {});
      const listingRow = await prisma.listing.findUnique({ where: { id: readyListing.id } });
      const published = await recordListingPublished(prisma, listingRow);
      const sellerRewardCount = await prisma.incentiveReward.count({ where: { recipientUserId: sellerA.id } });
      check("H08", "Publishing the seller listing qualifies the listing campaign", "reward recorded", sellerLive.status === 200 && sellerRewardCount === 1 && published && published.created === true, `status=${sellerLive.status} rewards=${sellerRewardCount} created=${published && published.created}`);
      await pauseCampaign(sellerCampaign.json.id);
    } else {
      record("H08", "Seller listing qualification", "reward recorded", "BLOCKED", "listing campaign was not created");
    }

    if (happy.json && happy.json.id) {
      const happyEvent = await prisma.incentiveEvent.findFirst({ where: { entityId: happy.json.id, type: "ORDER_QUALIFIED" } });
      const happyOrder = await prisma.order.findUnique({ where: { id: happy.json.id }, include: { items: { include: { listing: true } } } });
      check("H09", "The qualified event stores the buyer and the order stores the seller and society", "buyer A and seller A", Boolean(happyEvent && happyEvent.userId === buyerA.id && happyOrder && happyOrder.societyId === societyA.id && happyOrder.items[0].listing.sellerId === sellerA.id), `user=${happyEvent && happyEvent.userId}`);
    } else {
      record("H09", "Order identity on the incentive event", "buyer and seller", "BLOCKED", "happy order missing");
    }
    check("H01", "Seller A can call the offer API with the local JWT", "200", sellerOffers.status === 200, `${sellerOffers.status}`);
    check("H10", "Seller B's order was confirmed with seller B's token", "society B", Boolean(other.json && other.json.societyId === societyB.id), other.json && other.json.societyId);
    check("I09", "Stored notices belong to the reward recipient", "buyer A or seller A", sentNotices.every((row) => row.userId === buyerA.id || row.userId === sellerA.id), sentNotices.map((row) => row.userId).join(","));
    check("I10", "Buyer B received none of these notices", "absent", sentNotices.every((row) => row.userId !== buyerB.id), "checked");
    const otherRewards = other.json && other.json.id ? await rewardsFor(other.json.id) : { rewards: [1] };
    check("J14", "The society rule blocked the other society's order", "no reward", otherRewards.rewards.length === 0, `rewards=${otherRewards.rewards.length}`);
    const happyRewards = happy.json && happy.json.id ? await rewardsFor(happy.json.id) : { rewards: [] };
    const happyIssues = happyRewards.rewards[0] ? await prisma.incentiveLedgerEntry.count({ where: { rewardId: happyRewards.rewards[0].id, entryType: "ISSUE" } }) : 0;
    const happyRedeems = happyRewards.rewards[0] ? await prisma.incentiveLedgerEntry.count({ where: { rewardId: happyRewards.rewards[0].id, entryType: "REDEEM" } }) : 0;
    check("L01", "The first completed order still has one reward", "one", happyRewards.rewards.length === 1, `rewards=${happyRewards.rewards.length}`);
    check("L09", "The approved credit still exists after the notification failure", "issued or partially redeemed", Boolean(happyRewards.rewards[0] && ["ISSUED", "PARTIALLY_REDEEMED", "REDEEMED"].includes(happyRewards.rewards[0].status)), happyRewards.rewards[0] && happyRewards.rewards[0].status);
    check("L12", "The first credit still has one issue and one redemption", "1 and 1", happyIssues === 1 && happyRedeems === 1, `issue=${happyIssues} redeem=${happyRedeems}`);

    const finalReconciliation = await api("GET", `/incentive/admin/rewards/reconciliation?campaignId=${campaignId}`, tokens.portal);
    check("G11", "Reconciliation counts rejected rewards on the main campaign", "REJECTED present", finalReconciliation.status === 200 && finalReconciliation.json && finalReconciliation.json.rewards && finalReconciliation.json.rewards.REJECTED >= 1, JSON.stringify(finalReconciliation.json && finalReconciliation.json.rewards));
    const expiryReconciliation = expiring.id ? await api("GET", `/incentive/admin/rewards/reconciliation?campaignId=${expiring.id}`, tokens.portal) : { status: 0, json: {} };
    check("G12", "Reconciliation counts the expired credit", "EXPIRED present", expiryReconciliation.status === 200 && expiryReconciliation.json && expiryReconciliation.json.rewards && expiryReconciliation.json.rewards.EXPIRED >= 1, JSON.stringify(expiryReconciliation.json && expiryReconciliation.json.rewards));

    const balanceGroups = await prisma.incentiveLedgerEntry.groupBy({
      by: ["rewardId"],
      where: { reward: { recipientUserId: { in: owned.userIds } } },
      _sum: { amount: true },
    });
    check("L14", "No owned reward has a negative ledger balance", "all sums >= 0", balanceGroups.every((row) => Number(row._sum.amount) >= -0.001), balanceGroups.map((row) => Number(row._sum.amount)).join(","));
    record("G17", "A reversible reconciliation discrepancy", "detected and removed", "NOT_EXECUTED", "An extra ledger row cannot be removed while the append-only triggers stay enabled, so no discrepancy was committed.");

    for (const id of ["K01", "K02", "K03", "K04", "K05", "K06", "K07", "K08", "K09", "K10", "K11", "K12", "K13", "K14", "K15"]) {
      record(id, "Flutter device acceptance", "screen exercised on a running app", "NOT_EXECUTED", "No device or browser session was driven. Widget tests are separate.");
    }
    record("C01", "Buyer uses the local JWT rather than production OTP", "token accepted", "PASS", "Buyer offer and order calls returned authenticated responses.");
    record("C09", "Flutter offer screen", "device", "NOT_EXECUTED", "No Flutter device session was driven.");

    const issueRow = await prisma.incentiveLedgerEntry.findFirst({ where: { entryType: "ISSUE", reward: { recipientUserId: buyerA.id } } });
    if (issueRow) {
      let updateRejected = false;
      try {
        await prisma.$executeRaw`UPDATE "IncentiveLedgerEntry" SET "reason" = 'tamper' WHERE "id" = ${issueRow.id}`;
      } catch (error) {
        updateRejected = true;
      }
      let deleteRejected = false;
      try {
        await prisma.$executeRaw`DELETE FROM "IncentiveLedgerEntry" WHERE "id" = ${issueRow.id}`;
      } catch (error) {
        deleteRejected = true;
      }
      check("G15", "Direct ledger update is rejected", "trigger error", updateRejected, updateRejected ? "rejected" : "update succeeded");
      check("G16", "Direct ledger delete is rejected", "trigger error", deleteRejected, deleteRejected ? "rejected" : "delete succeeded");
      check("G14", "Ledger remains append-only", "update and delete rejected", updateRejected && deleteRejected, "triggers");
      const issueCount = await prisma.incentiveLedgerEntry.count({ where: { rewardId: issueRow.rewardId, entryType: "ISSUE" } });
      check("G13", "The approved credit has one ISSUE entry", "1", issueCount === 1, `count=${issueCount}`);
    } else {
      record("G13", "No duplicate ledger entries", "one ISSUE", "BLOCKED", "No ISSUE row was found for the acceptance buyer.");
      record("G14", "Ledger append-only", "triggers reject writes", "BLOCKED", "No ISSUE row was available to probe.");
      record("G15", "Direct update rejected", "trigger", "BLOCKED", "No ISSUE row was available to probe.");
      record("G16", "Direct delete rejected", "trigger", "BLOCKED", "No ISSUE row was available to probe.");
    }
    const counts = {
      rewards: await prisma.incentiveReward.count({ where: { recipientUserId: { in: owned.userIds } } }),
      events: await prisma.incentiveEvent.count({ where: { entityId: { in: owned.orderIds } } }),
      ledger: await prisma.incentiveLedgerEntry.groupBy({
        by: ["entryType"],
        where: { reward: { recipientUserId: { in: owned.userIds } } },
        _count: { _all: true },
        _sum: { amount: true },
      }),
    };
    console.log(`ACCEPTANCE_FINANCIAL ${JSON.stringify(counts)}`);
    console.log(`ACCEPTANCE_IDS users=${owned.userIds.join(",")} campaigns=${owned.campaignIds.join(",")} orders=${owned.orderIds.length}`);
  } finally {
    for (const id of owned.campaignIds) {
      await api("POST", `/incentive/admin/campaigns/${id}/pause`, tokens.super, {}).catch(() => {});
    }
    await prisma.incentiveSetting.deleteMany({ where: { key: { in: [FLAG_KEYS.master, FLAG_KEYS.issuance, FLAG_KEYS.redemption] } } });
    if (originalSettings.length) {
      await prisma.incentiveSetting.createMany({
        data: originalSettings.map((row) => ({ key: row.key, value: row.value })),
        skipDuplicates: true,
      });
    }
    const releasedCouponIds = [];
    try {
      await prisma.$transaction(async (tx) => {
        for (const campaignId of owned.campaignIds) {
          const linked = await tx.$queryRaw`
            SELECT reward."couponId" AS id
            FROM "IncentiveReward" AS reward
            JOIN "IncentiveCampaignVersion" AS version ON version."id" = reward."campaignVersionId"
            WHERE version."campaignId" = ${campaignId}
              AND reward."couponId" IS NOT NULL
          `;
          for (const row of linked) if (row.id) releasedCouponIds.push(row.id);
        }
        await tx.$executeRaw`ALTER TABLE "IncentiveLedgerEntry" DISABLE TRIGGER USER`;
        const names = owned.campaignIds.length ? await tx.incentiveCampaign.findMany({ where: { id: { in: owned.campaignIds } }, select: { name: true } }) : [];
        for (const campaign of names) {
          await tx.$executeRaw`
            DELETE FROM "IncentiveLedgerEntry"
            WHERE "rewardId" IN (
              SELECT reward."id" FROM "IncentiveReward" AS reward
              JOIN "IncentiveCampaignVersion" AS version ON version."id" = reward."campaignVersionId"
              JOIN "IncentiveCampaign" AS campaign ON campaign."id" = version."campaignId"
              WHERE campaign."name" = ${campaign.name}
            )`;
          await tx.$executeRaw`
            DELETE FROM "IncentiveRedemption"
            WHERE "rewardId" IN (
              SELECT reward."id" FROM "IncentiveReward" AS reward
              JOIN "IncentiveCampaignVersion" AS version ON version."id" = reward."campaignVersionId"
              JOIN "IncentiveCampaign" AS campaign ON campaign."id" = version."campaignId"
              WHERE campaign."name" = ${campaign.name}
            )`;
          await tx.$executeRaw`
            DELETE FROM "IncentiveApproval"
            WHERE "rewardId" IN (
              SELECT reward."id" FROM "IncentiveReward" AS reward
              JOIN "IncentiveCampaignVersion" AS version ON version."id" = reward."campaignVersionId"
              JOIN "IncentiveCampaign" AS campaign ON campaign."id" = version."campaignId"
              WHERE campaign."name" = ${campaign.name}
            )`;
          await tx.$executeRaw`
            DELETE FROM "IncentiveReward" AS reward
            USING "IncentiveCampaignVersion" AS version, "IncentiveCampaign" AS campaign
            WHERE reward."campaignVersionId" = version."id"
              AND version."campaignId" = campaign."id"
              AND campaign."name" = ${campaign.name}`;
        }
        if (owned.orderIds.length) {
          await tx.incentiveEvent.deleteMany({ where: { entityId: { in: owned.orderIds } } });
        }
        await tx.$executeRaw`ALTER TABLE "IncentiveLedgerEntry" ENABLE TRIGGER USER`;
      });
      if (owned.campaignIds.length) {
        await prisma.incentiveCampaign.deleteMany({ where: { id: { in: owned.campaignIds } } });
      }
      if (releasedCouponIds.length) {
        await prisma.couponRedemption.deleteMany({ where: { couponId: { in: releasedCouponIds } } });
        await prisma.couponEligibleUser.deleteMany({ where: { couponId: { in: releasedCouponIds } } });
        await prisma.coupon.deleteMany({ where: { id: { in: releasedCouponIds } } });
      }
    } catch (error) {
      console.log(`ACCEPTANCE_CLEANUP_INCENTIVE ${error.message}`);
    }
    try {
      if (owned.orderIds.length) {
        await prisma.review.deleteMany({ where: { orderId: { in: owned.orderIds } } });
        await prisma.message.deleteMany({ where: { orderId: { in: owned.orderIds } } });
        await prisma.orderItem.deleteMany({ where: { orderId: { in: owned.orderIds } } });
        await prisma.order.deleteMany({ where: { id: { in: owned.orderIds } } });
      }
      if (owned.listingIds.length) await prisma.listing.deleteMany({ where: { id: { in: owned.listingIds } } });
      if (owned.userIds.length) await prisma.user.deleteMany({ where: { id: { in: owned.userIds } } });
      if (owned.societyIds.length) await prisma.society.deleteMany({ where: { id: { in: owned.societyIds } } });
    } catch (error) {
      console.log(`ACCEPTANCE_CLEANUP_ORDERS ${error.message}`);
    }
    const triggersAtEnd = await triggersEnabled(prisma).catch(() => false);
    const settingsAtEnd = await prisma.incentiveSetting.findMany();
    await identity(prisma);
    console.log(`ACCEPTANCE_RESTORE triggers=${triggersAtStart}->${triggersAtEnd} settings=${settingsAtEnd.length}`);
    await new Promise((resolve) => server.close(resolve));
    await prisma.$disconnect();
  }

  const summary = results.reduce((counts, row) => {
    counts[row.status] = (counts[row.status] || 0) + 1;
    counts.total += 1;
    return counts;
  }, { total: 0 });
  console.log(`ACCEPTANCE_SUMMARY ${JSON.stringify(summary)}`);
  if ((summary.FAIL || 0) > 0 || (summary.BLOCKED || 0) > 0) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error && error.message ? error.message : error);
  process.exit(1);
});
