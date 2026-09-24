const assert = require("assert");
const {
  campaignBuyerHomePhase,
  isCampaignVisibleOnBuyerHome,
  assertCampaignAcceptsOrders,
} = require("../lib/preorder");

const now = new Date("2026-09-28T21:00:00.000Z");
const campaign = {
  status: "closed",
  orderOpenAt: "2026-09-25T10:00:00.000Z",
  orderCutoffAt: "2026-09-28T20:00:00.000Z",
  fulfilmentAt: "2026-09-30T19:00:00.000Z",
};

assert.strictEqual(
  campaignBuyerHomePhase(
    { ...campaign, status: "open" },
    new Date("2026-09-24T12:00:00.000Z")
  ),
  "upcoming",
  "published before open is upcoming"
);
assert.strictEqual(
  campaignBuyerHomePhase(
    { ...campaign, status: "open" },
    new Date("2026-09-26T12:00:00.000Z")
  ),
  "open",
  "during window is open"
);
assert.strictEqual(
  campaignBuyerHomePhase(campaign, now),
  "orders_closed",
  "after cutoff stays visible as orders_closed"
);
assert.strictEqual(
  isCampaignVisibleOnBuyerHome(campaign, now),
  true,
  "closed campaign remains on home until fulfilment"
);
assert.strictEqual(
  isCampaignVisibleOnBuyerHome(campaign, new Date("2026-09-30T19:00:00.000Z")),
  false,
  "hidden at fulfilmentAt"
);
assert.strictEqual(
  isCampaignVisibleOnBuyerHome({ ...campaign, status: "draft" }, now),
  false,
  "draft never on home"
);

let blocked = false;
try {
  assertCampaignAcceptsOrders(campaign, now);
} catch (err) {
  blocked = err.statusCode === 400;
}
assert.ok(blocked, "closed campaign cannot accept new orders");

let upcomingBlocked = false;
try {
  assertCampaignAcceptsOrders(
    { ...campaign, status: "open" },
    new Date("2026-09-24T12:00:00.000Z")
  );
} catch (err) {
  upcomingBlocked = err.message.includes("not open yet");
}
assert.ok(upcomingBlocked, "upcoming campaign cannot accept orders");

console.log("preorder-home-visibility.test.js passed");
