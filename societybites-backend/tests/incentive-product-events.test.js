process.env.DATABASE_URL = "postgresql://postgres@127.0.0.1:5432/societybites_incentive_unit";
process.env.DIRECT_URL = process.env.DATABASE_URL;

const fs = require("fs");
const path = require("path");
const http = require("http");
const express = require("express");
const { isBecomingSeller } = require("../lib/sellerTerms");
const { publishDraftListings, withCreatePublication } = require("../lib/listingPublish");
const { createEventsRouter } = require("../modules/incentive-engine/routes/adminEvents");
const {
  afterCommit,
  backfillProductEvents,
  emitOrderQualifiedIfReady,
  qualificationOccurredAt,
  recordCreatedPublications,
  recordListingPublished,
  recordSellerBecameSeller,
} = require("../modules/incentive-engine/events/productHooks");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function matches(row, where) {
  if (!where) return true;
  return Object.entries(where).every(([key, expected]) => {
    if (expected && typeof expected === "object" && !Array.isArray(expected) && !(expected instanceof Date)) {
      if (expected.in) return expected.in.includes(row[key]);
      if (Object.prototype.hasOwnProperty.call(expected, "not")) {
        if (expected.not === null) return row[key] != null;
        return row[key] !== expected.not;
      }
      return true;
    }
    return row[key] === expected;
  });
}

function memoryEvents() {
  const events = [];
  return {
    events,
    incentiveEvent: {
      async create({ data }) {
        if (events.some((row) => row.eventId === data.eventId)) {
          const error = new Error("Unique constraint failed on the fields: (`eventId`)");
          error.code = "P2002";
          error.meta = { modelName: "IncentiveEvent", target: ["eventId"] };
          throw error;
        }
        const row = { id: `event-${events.length + 1}`, ...data };
        events.push(row);
        return row;
      },
      async findUnique({ where }) {
        return events.find((row) => row.eventId === where.eventId || row.id === where.id) || null;
      },
      async findFirst({ where }) {
        return events.find((row) => row.entityType === where.entityType && row.entityId === where.entityId && where.type.in.includes(row.type)) || null;
      },
    },
  };
}

function order(overrides = {}) {
  return {
    id: "order-1",
    buyerId: "buyer-1",
    status: "completed",
    paymentMethod: "upi",
    paymentStatus: "seller_confirmed",
    paymentProvider: null,
    societyId: "soc-1",
    fulfilmentMethod: "pickup",
    deliveryCharge: 0,
    completedAt: new Date("2026-11-18T12:00:00.000Z"),
    sellerConfirmedPaidAt: new Date("2026-11-18T11:00:00.000Z"),
    deliveryCashConfirmedAt: null,
    createdAt: new Date("2026-11-17T00:00:00.000Z"),
    updatedAt: new Date("2026-11-19T00:00:00.000Z"),
    items: [{ listing: { sellerId: "seller-1", societyId: "soc-1" } }],
    ...overrides,
  };
}

function listingStore(seed) {
  const rows = seed.map((row) => ({ ...row }));
  const api = {
    async findMany({ where, select }) {
      return rows.filter((row) => matches(row, where)).map((row) => project(row, select));
    },
    async updateMany({ where, data }) {
      const matched = rows.filter((row) => matches(row, where));
      for (const row of matched) Object.assign(row, data);
      return { count: matched.length };
    },
  };
  return {
    rows,
    $transaction: (work) => work({ listing: api }),
  };
}

function project(row, select) {
  if (!select) return { ...row };
  const copy = {};
  for (const key of Object.keys(select)) if (select[key]) copy[key] = row[key];
  return copy;
}

async function testSeller() {
  assert(isBecomingSeller({ role: "buyer" }) === true, "buyer becomes a seller");
  assert(isBecomingSeller({ role: "seller" }) === false, "existing seller does not emit again");
  assert(isBecomingSeller({ role: "super_admin" }) === false, "super admin is not a seller activation");
  const source = fs.readFileSync(path.join(__dirname, "../lib/sellerTerms.js"), "utf8");
  const transactionAt = source.indexOf("const result = await prisma.$transaction");
  const emitAt = source.indexOf("recordSellerBecameSeller(prisma");
  assert(transactionAt > 0 && emitAt > transactionAt, "seller event is recorded after the terms transaction");
  assert(source.includes("if (!becomingSeller) return result"), "existing seller returns before the event");

  const db = memoryEvents();
  const acceptedAt = new Date("2026-11-17T08:00:00.000Z");
  const first = await recordSellerBecameSeller(db, { userId: "user-1", occurredAt: acceptedAt });
  const second = await recordSellerBecameSeller(db, { userId: "user-1", occurredAt: acceptedAt });
  assert(first.created === true, "seller activation inserts one event");
  assert(first.event.eventId === "USER_BECAME_SELLER:user-1", "seller event identity");
  assert(first.event.occurredAt === acceptedAt.toISOString(), "seller occurredAt is acceptedAt");
  assert(second.created === false && db.events.length === 1, "repeated seller activation is idempotent");
}

async function testListings() {
  const now = new Date("2026-11-17T09:00:00.000Z");
  const db = listingStore([
    { id: "draft-1", sellerId: "seller-1", status: "draft", firstPublishedAt: null },
    { id: "draft-2", sellerId: "seller-1", status: "draft", firstPublishedAt: null },
    { id: "paused-1", sellerId: "seller-1", status: "paused", firstPublishedAt: null },
  ]);
  const published = await publishDraftListings(db, { sellerId: "seller-1", ids: ["draft-1", "draft-2"], now });
  assert(published.publishedCount === 2, "both drafts publish");
  assert(published.stamped.length === 2, "both drafts receive a first publication time");
  assert(db.rows.find((row) => row.id === "paused-1").status === "paused", "paused listing is not published");
  const again = await publishDraftListings(db, {
    sellerId: "seller-1",
    ids: ["draft-1"],
    now: new Date("2026-11-18T09:00:00.000Z"),
  });
  assert(again.publishedCount === 0 && again.stamped.length === 0, "active listing is not published again");
  assert(db.rows.find((row) => row.id === "draft-1").firstPublishedAt.toISOString() === now.toISOString(), "firstPublishedAt is set once");

  const events = memoryEvents();
  const saved = await recordListingPublished(events, published.stamped[0]);
  const repeat = await recordListingPublished(events, published.stamped[0]);
  assert(saved.event.eventId === "LISTING_PUBLISHED:draft-1", "listing event identity");
  assert(saved.event.occurredAt === now.toISOString(), "listing occurredAt is firstPublishedAt");
  assert(repeat.created === false && events.events.length === 1, "repeated publication event is idempotent");

  const routes = fs.readFileSync(path.join(__dirname, "../routes/listings.js"), "utf8");
  const resume = routes.slice(routes.indexOf('"/bulk/resume"'), routes.indexOf('"/:id/publish"'));
  const singleResume = routes.slice(routes.indexOf('"/:id/resume"'), routes.indexOf("router.delete"));
  assert(!resume.includes("firstPublishedAt") && !resume.includes("emitPublishedListings"), "bulk resume does not emit first publication");
  assert(!singleResume.includes("firstPublishedAt") && !singleResume.includes("emitPublishedListings"), "resume and renew do not emit first publication");
}

function createStore() {
  const rows = [];
  let sequence = 0;
  const listing = {
    async create({ data }) {
      const row = {
        id: `created-${++sequence}`,
        sellerId: data.sellerId,
        status: data.status,
        variantLabel: data.variantLabel || null,
        firstPublishedAt: Object.prototype.hasOwnProperty.call(data, "firstPublishedAt")
          ? data.firstPublishedAt
          : null,
        createdAt: new Date("2020-01-01T00:00:00.000Z"),
        updatedAt: new Date("2020-01-02T00:00:00.000Z"),
      };
      rows.push(row);
      return { ...row };
    },
  };
  return {
    rows,
    $transaction: (work) => work({ listing }),
  };
}

async function testCreatePublication() {
  const now = new Date("2026-11-17T10:00:00.000Z");
  const draftFields = withCreatePublication(
    { sellerId: "seller-1", status: "draft" },
    "draft",
    now
  );
  assert(!Object.prototype.hasOwnProperty.call(draftFields, "firstPublishedAt"), "draft create data has no publication time");

  const draftEvents = memoryEvents();
  const drafted = await createStore().$transaction((tx) =>
    tx.listing.create({ data: draftFields })
  );
  const draftBody = { id: drafted.id, status: "draft" };
  const draftResponse = await recordCreatedPublications(draftEvents, draftBody, [drafted]);
  assert(drafted.firstPublishedAt == null, "draft listing is not stamped");
  assert(draftResponse === draftBody && draftEvents.events.length === 0, "draft creation does not emit");

  const singleEvents = memoryEvents();
  const created = await createStore().$transaction((tx) => {
    const publishedAt = now;
    return tx.listing.create({
      data: withCreatePublication({ sellerId: "seller-1", status: "active" }, "active", publishedAt),
    });
  });
  assert(created.firstPublishedAt === now, "single publish-now stamps the server time");
  assert(created.createdAt.toISOString() !== now.toISOString(), "publication time is not createdAt");
  assert(created.updatedAt.toISOString() !== now.toISOString(), "publication time is not updatedAt");
  const body = { id: created.id, status: "active" };
  const firstResponse = await recordCreatedPublications(singleEvents, body, [created]);
  const secondResponse = await recordCreatedPublications(singleEvents, body, [created]);
  assert(firstResponse === body && secondResponse === body, "listing creation response is unchanged");
  assert(singleEvents.events.length === 1, "single publish-now emits one event");
  assert(singleEvents.events[0].eventId === `LISTING_PUBLISHED:${created.id}`, "single listing event id");
  assert(singleEvents.events[0].occurredAt.toISOString() === now.toISOString(), "occurredAt is the persisted firstPublishedAt");

  const variantEvents = memoryEvents();
  const variants = await createStore().$transaction((tx) => {
    const publishedAt = now;
    return Promise.all(
      ["Half", "Full"].map((variantLabel) =>
        tx.listing.create({
          data: withCreatePublication(
            { sellerId: "seller-1", status: "active", variantLabel },
            "active",
            publishedAt
          ),
        })
      )
    );
  });
  assert(variants.length === 2, "both variants are created");
  assert(variants.every((row) => row.firstPublishedAt === now), "each variant receives the same server publication time");
  const variantBody = { id: variants[0].id, status: "active" };
  await recordCreatedPublications(variantEvents, variantBody, variants);
  await recordCreatedPublications(variantEvents, variantBody, variants);
  assert(variantEvents.events.length === 2, "each variant emits once and a repeat does not duplicate");
  assert(
    variantEvents.events.map((row) => row.eventId).sort().join(",") ===
      variants.map((row) => `LISTING_PUBLISHED:${row.id}`).sort().join(","),
    "variant event ids match the created listings"
  );

  const failing = memoryEvents();
  failing.incentiveEvent.create = async () => {
    throw new Error("incentive database unavailable");
  };
  const failed = await recordCreatedPublications(failing, body, [created]);
  assert(failed.id === body.id && failed.status === "active", "incentive failure does not fail listing creation");

  const routes = fs.readFileSync(path.join(__dirname, "../routes/listings.js"), "utf8");
  const secondPost = routes.indexOf("router.post(", routes.indexOf("router.post(") + 1);
  const createRoute = routes.slice(secondPost, routes.indexOf('"/catalog-order"'));
  const firstTransaction = createRoute.indexOf("prisma.$transaction");
  const firstRecord = createRoute.indexOf("recordCreatedPublications");
  const secondTransaction = createRoute.indexOf("prisma.$transaction", firstTransaction + 1);
  const secondRecord = createRoute.indexOf("recordCreatedPublications", firstRecord + 1);
  assert((createRoute.match(/withCreatePublication/g) || []).length === 2, "both create paths stamp inside the transaction");
  assert(firstTransaction > 0 && firstRecord > firstTransaction, "variant event follows the create transaction");
  assert(secondTransaction > firstRecord && secondRecord > secondTransaction, "single event follows the create transaction");
}

async function testOrders() {
  const direct = qualificationOccurredAt(order());
  assert(direct.toISOString() === "2026-11-18T12:00:00.000Z", "direct UPI uses the later business timestamp");
  const cash = qualificationOccurredAt(order({
    paymentMethod: "cash",
    paymentStatus: "paid",
    sellerConfirmedPaidAt: new Date("2026-11-18T12:30:00.000Z"),
  }));
  assert(cash.toISOString() === "2026-11-18T12:30:00.000Z", "cash uses the confirmation timestamp");
  const gateway = qualificationOccurredAt(order({
    paymentMethod: "upi",
    paymentProvider: "cashfree",
    paymentStatus: "paid",
    sellerConfirmedPaidAt: new Date("2026-11-18T10:00:00.000Z"),
  }));
  assert(gateway.toISOString() === "2026-11-18T12:00:00.000Z", "cashfree uses completion when it is later");
  const outsideCash = qualificationOccurredAt(order({
    paymentMethod: "cash",
    paymentStatus: "paid",
    fulfilmentMethod: "seller_delivery",
    societyId: "buyer-soc",
    sellerConfirmedPaidAt: new Date("2026-11-18T13:00:00.000Z"),
    items: [{ listing: { sellerId: "seller-1", societyId: "seller-soc" } }],
  }));
  assert(outsideCash.toISOString() === "2026-11-18T13:00:00.000Z", "outside cash uses the paid timestamp");
  const split = qualificationOccurredAt(order({
    paymentMethod: "upi",
    paymentStatus: "seller_confirmed",
    fulfilmentMethod: "seller_delivery",
    societyId: "buyer-soc",
    deliveryCharge: 25,
    deliveryCashConfirmedAt: new Date("2026-11-18T12:45:00.000Z"),
    items: [{ listing: { sellerId: "seller-1", societyId: "seller-soc" } }],
  }));
  assert(split.toISOString() === "2026-11-18T12:45:00.000Z", "split payment uses delivery cash confirmation");
  assert(qualificationOccurredAt(order({ sellerConfirmedPaidAt: null, updatedAt: new Date("2026-11-20T00:00:00.000Z") })) === null, "missing confirmation time is not replaced by updatedAt");

  const db = memoryEvents();
  const stored = order();
  db.order = {
    async findUnique() {
      return stored;
    },
  };
  const first = await emitOrderQualifiedIfReady(db, stored.id);
  const second = await emitOrderQualifiedIfReady(db, stored.id);
  assert(first.created === true && first.event.eventId === "ORDER_QUALIFIED:order-1", "order event identity");
  assert(first.event.occurredAt === "2026-11-18T12:00:00.000Z", "order occurredAt");
  assert(second.created === false && db.events.length === 1, "repeated order event is idempotent");
  stored.sellerConfirmedPaidAt = null;
  const blocked = await emitOrderQualifiedIfReady(db, stored.id);
  assert(blocked.reason === "OCCURRED_AT_UNAVAILABLE" && db.events.length === 1, "incomplete timestamp does not emit");
}

async function testFailureIsolation() {
  let ran = false;
  const result = await afterCommit({ status: "completed", id: "order-1" }, async () => {
    ran = true;
    throw new Error("incentive database unavailable");
  });
  assert(ran === true, "incentive write was attempted");
  assert(result.status === "completed" && result.id === "order-1", "product result survives an incentive failure");
}

async function testBackfill() {
  const db = memoryEvents();
  db.user = {
    async findMany() {
      return [{ id: "seller-1" }, { id: "seller-2" }];
    },
  };
  db.sellerTermsAcceptance = {
    async findMany() {
      return [
        { userId: "seller-1", acceptedAt: new Date("2026-11-02T00:00:00.000Z") },
        { userId: "seller-1", acceptedAt: new Date("2026-11-01T00:00:00.000Z") },
      ];
    },
  };
  db.listing = {
    async findMany({ where }) {
      if (where.firstPublishedAt && where.firstPublishedAt.not === null) {
        return [{ id: "listed-1", sellerId: "seller-1", firstPublishedAt: new Date("2026-11-03T00:00:00.000Z") }];
      }
      return [{ id: "old-1", status: "active" }];
    },
  };
  db.order = {
    async findMany() {
      return [order({ id: "order-9", buyerId: "buyer-9" })];
    },
    async findUnique({ where }) {
      return where.id === "order-9" ? order({ id: "order-9", buyerId: "buyer-9" }) : null;
    },
  };
  const first = await backfillProductEvents(db, { limit: 20 });
  const second = await backfillProductEvents(db, { limit: 20 });
  assert(first.sellers.inserted === 1 && first.sellers.unreconstructable.length === 1, "seller backfill reports a missing acceptance");
  assert(first.sellers.unreconstructable[0].userId === "seller-2", "unreconstructable seller id");
  assert(db.events.find((row) => row.eventId === "USER_BECAME_SELLER:seller-1").occurredAt.toISOString() === "2026-11-01T00:00:00.000Z", "earliest acceptance is used");
  assert(first.listings.inserted === 1, "stamped listing is backfilled");
  assert(first.listings.unreconstructable[0].reason === "FIRST_PUBLISHED_AT_UNAVAILABLE", "historical listing is reported");
  assert(!db.events.some((row) => row.entityId === "old-1"), "historical listing does not get an invented event");
  assert(first.orders.inserted === 1 && db.events.some((row) => row.eventId === "ORDER_QUALIFIED:order-9"), "qualified order is backfilled");
  assert(second.sellers.existing === 1 && second.listings.existing === 1 && second.orders.existing === 1, "backfill is idempotent");
  assert(db.events.length === 3, "backfill does not duplicate events");
}

async function testAdmin() {
  let calls = 0;
  const router = createEventsRouter({
    repository: {},
    requireUser: (req, res, next) => (req.user ? next() : res.status(401).json({ error: "Sign in required" })),
    requireAdmin: (req, res, next) => (req.user.role === "admin" || req.user.role === "super_admin" ? next() : res.status(403).json({ error: "Admin only" })),
    requireSuperAdmin: (req, res, next) => {
      if (req.user.role === "super_admin") return next();
      res.status(403).json({ error: "Super admin only" });
      return undefined;
    },
    backfill: async () => {
      calls += 1;
      return { ok: true };
    },
  });
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    req.user = req.headers["x-role"] ? { id: "admin-1", role: req.headers["x-role"] } : null;
    next();
  });
  app.use(router);
  const server = await new Promise((resolve) => {
    const listening = http.createServer(app);
    listening.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const denied = await new Promise((resolve, reject) => {
      const req = http.request(
        { hostname: "127.0.0.1", port: server.address().port, path: "/events/backfill", method: "POST", headers: { "x-role": "admin", "Content-Length": "2" } },
        (res) => {
          let data = "";
          res.on("data", (chunk) => { data += chunk; });
          res.on("end", () => resolve({ status: res.statusCode, json: JSON.parse(data) }));
        }
      );
      req.on("error", reject);
      req.end("{}");
    });
    assert(denied.status === 403 && calls === 0, "portal admin cannot backfill");
    const allowed = await new Promise((resolve, reject) => {
      const req = http.request(
        { hostname: "127.0.0.1", port: server.address().port, path: "/events/backfill", method: "POST", headers: { "x-role": "super_admin", "Content-Length": "2" } },
        (res) => {
          let data = "";
          res.on("data", (chunk) => { data += chunk; });
          res.on("end", () => resolve({ status: res.statusCode, json: JSON.parse(data) }));
        }
      );
      req.on("error", reject);
      req.end("{}");
    });
    assert(allowed.status === 200 && allowed.json.ok === true && calls === 1, "super admin can backfill");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

async function main() {
  await testSeller();
  await testListings();
  await testCreatePublication();
  await testOrders();
  await testFailureIsolation();
  await testBackfill();
  await testAdmin();
  console.log("incentive product events ok");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
