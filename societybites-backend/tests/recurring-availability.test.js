require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const listingRoutes = require("../routes/listings");
const orderRoutes = require("../routes/orders");
const {
  evaluateRecurringAvailability,
  recurringWriteFields,
  istClock,
} = require("../lib/recurringAvailability");

const SEED_BUYER_PHONE = "+919845154070";
const SEED_SELLER_PHONE = "+919901844776";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function jsonRequest(server, { method, path, token, body }) {
  const addr = server.address();
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : Buffer.from(JSON.stringify(body));
    const req = http.request(
      {
        hostname: "127.0.0.1",
        port: addr.port,
        path,
        method,
        headers: {
          Accept: "application/json",
          ...(payload && {
            "Content-Type": "application/json",
            "Content-Length": String(payload.length),
          }),
          ...(token && { Authorization: `Bearer ${token}` }),
        },
      },
      (res) => {
        let data = "";
        res.on("data", (c) => (data += c));
        res.on("end", () => {
          let json = null;
          try {
            json = data ? JSON.parse(data) : null;
          } catch (_) {
            json = data;
          }
          resolve({ status: res.statusCode, json });
        });
      }
    );
    req.on("error", reject);
    if (payload) req.write(payload);
    req.end();
  });
}

async function main() {
  const mondayMorning = new Date("2026-09-28T02:00:00.000Z");
  const mondayNoon = new Date("2026-09-28T06:30:00.000Z");
  const tuesdayMorning = new Date("2026-09-29T02:00:00.000Z");
  const listing = {
    catalogType: "REGULAR",
    availabilityMode: "READY_NOW",
    recurringEnabled: true,
    recurringWeekdays: [1, 2, 3, 4, 5, 6],
    recurringStartMinute: 420,
    recurringEndMinute: 660,
    recurringDailyLimit: 20,
    status: "active",
    name: "Idli",
  };

  const open = evaluateRecurringAvailability(listing, { now: mondayMorning });
  assert(open.recurringUnavailable === false, "Mon 7:30 IST should be available");
  assert(open.recurringBuyerLabel.includes("Until 11:00 AM"), open.recurringBuyerLabel);

  const stringDays = evaluateRecurringAvailability(
    { ...listing, recurringWeekdays: ["1", "2", "3", "4", "5", "6"] },
    { now: mondayMorning }
  );
  assert(stringDays.recurringUnavailable === false, "weekday values may be strings");

  const sundayListing = {
    ...listing,
    recurringWeekdays: [7],
    recurringStartMinute: 0,
    recurringEndMinute: 1439,
  };
  const sunday = evaluateRecurringAvailability(sundayListing, {
    now: new Date("2026-09-27T05:00:00.000Z"),
  });
  assert(sunday.recurringUnavailable === false, "Sunday full-day listing is orderable");

  const closed = evaluateRecurringAvailability(listing, { now: mondayNoon });
  assert(closed.recurringUnavailable === true, "Mon noon IST should be unavailable");
  assert(closed.recurringNextLabel.includes("tomorrow"), closed.recurringNextLabel);

  const nextDay = evaluateRecurringAvailability(listing, { now: tuesdayMorning });
  assert(nextDay.recurringUnavailable === false, "Tue 7:30 IST should be available again");

  const soldOut = evaluateRecurringAvailability(listing, {
    now: mondayMorning,
    soldToday: 20,
  });
  assert(soldOut.recurringUnavailable === true, "daily limit should close listing");
  assert(soldOut.recurringNextLabel.includes("Sold out"), soldOut.recurringNextLabel);

  const paused = evaluateRecurringAvailability(
    { ...listing, status: "paused" },
    { now: mondayMorning }
  );
  assert(paused.recurringUnavailable === true, "paused stays unavailable in window");

  const normal = evaluateRecurringAvailability(
    { catalogType: "REGULAR", availabilityMode: "READY_NOW", status: "active" },
    { now: mondayMorning }
  );
  assert(normal.recurringEnabled === false, "unscheduled listing is unchanged");

  const sameDaySaved = recurringWriteFields(
    {
      sameDayHours: true,
      recurringStartMinute: 420,
      recurringEndMinute: 660,
    },
    { catalogType: "REGULAR", availabilityMode: "READY_NOW" }
  );
  assert(sameDaySaved.recurringEnabled === false, "today hours are not weekly");
  assert(sameDaySaved.recurringStartMinute === 420, "today start saved");
  assert(sameDaySaved.recurringEndMinute === 660, "today end saved");

  const morningWait = evaluateRecurringAvailability(
    {
      catalogType: "REGULAR",
      availabilityMode: "READY_NOW",
      status: "active",
      recurringEnabled: false,
      recurringStartMinute: 420,
      recurringEndMinute: 660,
    },
    { now: new Date("2026-09-28T00:30:00.000Z") }
  );
  assert(morningWait.recurringUnavailable === true, "before today window is unavailable");
  assert(
    morningWait.recurringNextLabel.includes("7:00 AM"),
    morningWait.recurringNextLabel
  );

  try {
    recurringWriteFields(
      { recurringEnabled: true, recurringWeekdays: [1], recurringStartMinute: 660, recurringEndMinute: 420 },
      { catalogType: "REGULAR", availabilityMode: "READY_NOW" }
    );
    throw new Error("invalid time range should throw");
  } catch (err) {
    assert(err.statusCode === 400, "invalid time range is 400");
  }

  try {
    recurringWriteFields(
      { recurringEnabled: true, recurringWeekdays: [1], recurringStartMinute: 420, recurringEndMinute: 660 },
      { catalogType: "PREORDER", availabilityMode: "READY_NOW" }
    );
    throw new Error("preorder recurring should throw");
  } catch (err) {
    assert(String(err.message).includes("Pre-order"), err.message);
  }

  try {
    recurringWriteFields(
      { recurringEnabled: true, recurringWeekdays: [1], recurringStartMinute: 420, recurringEndMinute: 660 },
      { catalogType: "REGULAR", availabilityMode: "MADE_TO_ORDER" }
    );
    throw new Error("mto recurring should throw");
  } catch (err) {
    assert(String(err.message).includes("Made to order"), err.message);
  }

  const seller = await prisma.user.findUnique({ where: { phone: SEED_SELLER_PHONE } });
  const buyer = await prisma.user.findUnique({ where: { phone: SEED_BUYER_PHONE } });
  assert(seller && buyer, "seed users required");
  const sellerToken = signToken(seller);
  const buyerToken = signToken(buyer);
  const stamp = Date.now();
  const listingIds = [];
  const orderIds = [];

  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    const header = req.headers.authorization || "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : null;
    if (token === sellerToken) req.user = seller;
    if (token === buyerToken) req.user = buyer;
    next();
  });
  app.use("/listings", listingRoutes);
  app.use("/orders", orderRoutes);

  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  try {
    const plain = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Plain ${stamp}`,
        price: 40,
        foodType: "VEG",
        category: "Breakfast",
        quantity: 8,
      },
    });
    assert(plain.status === 201, `plain create failed ${JSON.stringify(plain.json)}`);
    assert(plain.json.recurringEnabled === false, "existing create stays unscheduled");
    listingIds.push(plain.json.id);

    const saved = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Idli ${stamp}`,
        price: 60,
        foodType: "VEG",
        category: "Breakfast",
        quantity: 99,
        recurringEnabled: true,
        recurringWeekdays: [1, 2, 3, 4, 5, 6, 7],
        recurringStartMinute: 0,
        recurringEndMinute: 1439,
        recurringDailyLimit: 2,
      },
    });
    assert(saved.status === 201, `recurring create failed ${JSON.stringify(saved.json)}`);
    assert(saved.json.recurringEnabled === true, "schedule saved");
    assert(saved.json.recurringWeekdays.length === 7, "multiple days saved");
    assert(saved.json.recurringStartMinute === 0, "start saved");
    assert(saved.json.recurringEndMinute === 1439, "end saved");
    assert(saved.json.recurringDailyLimit === 2, "daily limit saved");
    assert(
      saved.json.recurringUnavailable === false,
      `full-day listing should be orderable now ${JSON.stringify({
        clock: istClock(),
        label: saved.json.recurringBuyerLabel,
        next: saved.json.recurringNextLabel,
      })}`
    );
    listingIds.push(saved.json.id);

    const badTime = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Bad time ${stamp}`,
        price: 40,
        foodType: "VEG",
        category: "Breakfast",
        recurringEnabled: true,
        recurringWeekdays: [1],
        recurringStartMinute: 600,
        recurringEndMinute: 500,
      },
    });
    assert(badTime.status === 400, "invalid time range rejected");

    const badLimit = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Bad limit ${stamp}`,
        price: 40,
        foodType: "VEG",
        category: "Breakfast",
        recurringEnabled: true,
        recurringWeekdays: [1],
        recurringStartMinute: 0,
        recurringEndMinute: 1439,
        recurringDailyLimit: 0,
      },
    });
    assert(badLimit.status === 400, "invalid daily limit rejected");

    const preorder = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Pre ${stamp}`,
        price: 90,
        foodType: "VEG",
        category: "Dinner",
        catalogType: "PREORDER",
        recurringEnabled: true,
        recurringWeekdays: [1],
        recurringStartMinute: 0,
        recurringEndMinute: 1439,
      },
    });
    assert(preorder.status === 400, "PREORDER recurring rejected");

    const mto = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `MTO ${stamp}`,
        price: 90,
        foodType: "VEG",
        category: "Dinner",
        availabilityMode: "MADE_TO_ORDER",
        preparationTimeMinutes: 60,
        recurringEnabled: true,
        recurringWeekdays: [1],
        recurringStartMinute: 0,
        recurringEndMinute: 1439,
      },
    });
    assert(mto.status === 400, "MADE_TO_ORDER recurring rejected");

    const first = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: saved.json.id, quantity: 2 }],
      },
    });
    assert(first.status === 201, `order during schedule failed ${JSON.stringify(first.json)}`);
    orderIds.push(first.json.id);

    const blocked = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: saved.json.id, quantity: 1 }],
      },
    });
    assert(blocked.status === 409 || blocked.status === 400, "daily limit blocks further orders");

    const paused = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${saved.json.id}/pause`,
      token: sellerToken,
    });
    assert(paused.status === 200, "pause recurring listing");
    assert(paused.json.recurringEnabled === true, "pause keeps schedule");

    const pausedOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: saved.json.id, quantity: 1 }],
      },
    });
    assert(pausedOrder.status === 400, "paused recurring cannot be ordered");

    const resumed = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${saved.json.id}/resume`,
      token: sellerToken,
    });
    assert(resumed.status === 200, "resume recurring listing");
    assert(resumed.json.recurringEnabled === true, "resume keeps schedule");
    assert(JSON.stringify(resumed.json.recurringWeekdays) === JSON.stringify([1, 2, 3, 4, 5, 6, 7]), "days intact");

    const sundayOnly = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${saved.json.id}`,
      token: sellerToken,
      body: {
        foodType: "VEG",
        recurringEnabled: true,
        recurringWeekdays: [istClock().weekday === 7 ? 1 : 7],
        recurringStartMinute: 0,
        recurringEndMinute: 1439,
        recurringDailyLimit: 20,
      },
    });
    assert(sundayOnly.status === 200, "update schedule");

    const outside = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: saved.json.id, quantity: 1 }],
      },
    });
    assert(outside.status === 400, "order outside configured day rejected");

    const regularOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: plain.json.id, quantity: 1 }],
      },
    });
    assert(regularOrder.status === 201, `normal listing order failed ${JSON.stringify(regularOrder.json)}`);
    orderIds.push(regularOrder.json.id);

    console.log("recurring-availability.test.js passed");
  } finally {
    server.close();
    if (orderIds.length) {
      await prisma.order.deleteMany({ where: { id: { in: orderIds } } });
    }
    if (listingIds.length) {
      await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
    }
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
