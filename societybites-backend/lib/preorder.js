const prisma = require("./prisma");

const CAMPAIGN_STATUSES = ["draft", "open", "closed", "cancelled"];
const FULFILMENT_METHODS = ["pickup", "seller_delivery"];
const INVENTORY_MODES = ["demand", "limited"];

function parseDate(value, field) {
  if (value == null || value === "") {
    const err = new Error(`${field} is required`);
    err.statusCode = 400;
    throw err;
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    const err = new Error(`${field} must be a valid date`);
    err.statusCode = 400;
    throw err;
  }
  return date;
}

function assertCampaignTimeline(orderOpenAt, orderCutoffAt, fulfilmentAt) {
  if (!(orderOpenAt < orderCutoffAt && orderCutoffAt < fulfilmentAt)) {
    const err = new Error("orderOpenAt must be before orderCutoffAt, which must be before fulfilmentAt");
    err.statusCode = 400;
    throw err;
  }
}

function normalizeFulfilmentMethods(raw) {
  const methods = Array.isArray(raw) && raw.length > 0 ? raw.map(String) : ["pickup"];
  const unique = [...new Set(methods)];
  if (unique.some((m) => !FULFILMENT_METHODS.includes(m))) {
    const err = new Error("offeredFulfilmentMethods must be pickup and/or seller_delivery");
    err.statusCode = 400;
    throw err;
  }
  return unique;
}

function normalizeInventoryMode(raw) {
  const mode = raw == null || raw === "" ? "demand" : String(raw);
  if (!INVENTORY_MODES.includes(mode)) {
    const err = new Error("inventoryMode must be demand or limited");
    err.statusCode = 400;
    throw err;
  }
  return mode;
}

function isLimitedCampaignListing(listing) {
  return Boolean(listing?.campaignId && listing.inventoryMode === "limited");
}

function shouldRestoreListingInventory(listing) {
  if (!listing) return false;
  if (!listing.campaignId) return true;
  return listing.inventoryMode === "limited";
}

async function lazyCloseCampaign(campaign, now = new Date()) {
  if (!campaign) return campaign;
  if (campaign.status !== "open") return campaign;
  if (new Date(campaign.orderCutoffAt) > now) return campaign;

  return prisma.preOrderCampaign.update({
    where: { id: campaign.id },
    data: { status: "closed" },
  });
}

function assertCampaignAcceptsOrders(campaign, now = new Date()) {
  if (!campaign) {
    const err = new Error("Pre-order campaign not found");
    err.statusCode = 404;
    throw err;
  }
  if (campaign.status === "cancelled") {
    const err = new Error("This pre-order campaign has been cancelled");
    err.statusCode = 400;
    throw err;
  }
  if (campaign.status === "draft") {
    const err = new Error("This pre-order campaign is not open yet");
    err.statusCode = 400;
    throw err;
  }
  if (now < new Date(campaign.orderOpenAt)) {
    const err = new Error("This pre-order campaign is not open yet");
    err.statusCode = 400;
    throw err;
  }
  if (now >= new Date(campaign.orderCutoffAt) || campaign.status === "closed") {
    const err = new Error("Pre-order cutoff has passed");
    err.statusCode = 400;
    throw err;
  }
}

async function campaignHasOrders(campaignId) {
  const count = await prisma.order.count({
    where: { campaignId, type: "pre_order" },
  });
  return count > 0;
}

function serializeCampaign(campaign) {
  if (!campaign) return null;
  return {
    id: campaign.id,
    sellerId: campaign.sellerId,
    societyId: campaign.societyId,
    title: campaign.title,
    description: campaign.description || null,
    coverImageUrl: campaign.coverImageUrl || null,
    fulfilmentNotes: campaign.fulfilmentNotes || null,
    orderOpenAt: campaign.orderOpenAt,
    orderCutoffAt: campaign.orderCutoffAt,
    fulfilmentAt: campaign.fulfilmentAt,
    status: campaign.status,
    offeredFulfilmentMethods: campaign.offeredFulfilmentMethods || ["pickup"],
    defaultDeliveryCharge: campaign.defaultDeliveryCharge || 0,
    createdAt: campaign.createdAt,
    updatedAt: campaign.updatedAt,
    products: Array.isArray(campaign.products) ? campaign.products : undefined,
  };
}

function requireSeller(user) {
  const role = user.role || "buyer";
  if (!["seller", "super_admin"].includes(role)) {
    const err = new Error("Enable selling in Profile before managing pre-orders");
    err.statusCode = 403;
    err.code = "SELLER_REQUIRED";
    throw err;
  }
  if (!user.societyId) {
    const err = new Error("You must join a society before managing pre-orders");
    err.statusCode = 400;
    throw err;
  }
}

const INVALID_DASHBOARD_STATUSES = ["cancelled", "rejected"];

function validCampaignOrderWhere(campaignId) {
  return {
    campaignId,
    type: "pre_order",
    status: { notIn: INVALID_DASHBOARD_STATUSES },
  };
}

function requireCampaignOwner(user, campaign) {
  if (!campaign) {
    const err = new Error("Pre-order campaign not found");
    err.statusCode = 404;
    throw err;
  }
  if (campaign.sellerId !== user.id) {
    const err = new Error("Not allowed to view this campaign dashboard");
    err.statusCode = 403;
    throw err;
  }
}

async function buildCampaignSummary(campaign) {
  const [products, orders] = await Promise.all([
    prisma.listing.findMany({
      where: { campaignId: campaign.id },
      orderBy: { createdAt: "asc" },
      select: { id: true, name: true },
    }),
    prisma.order.findMany({
      where: validCampaignOrderWhere(campaign.id),
      include: { items: true },
    }),
  ]);

  const qtyByListing = new Map();
  for (const product of products) {
    qtyByListing.set(product.id, 0);
  }

  let totalItems = 0;
  let foodSubtotal = 0;
  let pickup = 0;
  let sellerDelivery = 0;

  for (const order of orders) {
    foodSubtotal += Number(order.subtotal || 0);
    if (order.fulfilmentMethod === "seller_delivery") sellerDelivery += 1;
    else if (order.fulfilmentMethod === "pickup") pickup += 1;

    for (const item of order.items) {
      totalItems += item.quantity;
      qtyByListing.set(
        item.listingId,
        (qtyByListing.get(item.listingId) || 0) + item.quantity
      );
    }
  }

  return {
    campaignId: campaign.id,
    title: campaign.title,
    coverImageUrl: campaign.coverImageUrl || null,
    fulfilmentNotes: campaign.fulfilmentNotes || null,
    status: campaign.status,
    orderOpenAt: campaign.orderOpenAt,
    orderCutoffAt: campaign.orderCutoffAt,
    fulfilmentAt: campaign.fulfilmentAt,
    totalOrders: orders.length,
    totalItems,
    foodSubtotal,
    fulfilment: {
      pickup,
      seller_delivery: sellerDelivery,
    },
    products: products.map((product) => ({
      listingId: product.id,
      productName: product.name,
      quantityToPrepare: qtyByListing.get(product.id) || 0,
    })),
  };
}

module.exports = {
  CAMPAIGN_STATUSES,
  FULFILMENT_METHODS,
  INVENTORY_MODES,
  INVALID_DASHBOARD_STATUSES,
  parseDate,
  assertCampaignTimeline,
  normalizeFulfilmentMethods,
  normalizeInventoryMode,
  isLimitedCampaignListing,
  shouldRestoreListingInventory,
  lazyCloseCampaign,
  assertCampaignAcceptsOrders,
  campaignHasOrders,
  serializeCampaign,
  requireSeller,
  requireCampaignOwner,
  validCampaignOrderWhere,
  buildCampaignSummary,
};
