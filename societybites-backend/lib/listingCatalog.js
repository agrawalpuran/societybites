const CATALOG_TYPES = ["REGULAR", "PREORDER"];
const ACTIVE_CAMPAIGN_STATUSES = ["draft", "open"];

function parseCatalogType(value, { required = false, defaultValue = "REGULAR" } = {}) {
  if (value == null || value === "") {
    if (required) {
      const err = new Error("catalogType must be REGULAR or PREORDER");
      err.statusCode = 400;
      throw err;
    }
    return defaultValue;
  }
  const raw = String(value).trim().toUpperCase();
  if (!CATALOG_TYPES.includes(raw)) {
    const err = new Error("catalogType must be REGULAR or PREORDER");
    err.statusCode = 400;
    throw err;
  }
  return raw;
}

function regularMarketplaceWhere() {
  return {
    campaignId: null,
    catalogType: "REGULAR",
  };
}

function catalogListWhere({ catalogType, sellerId, userId }) {
  const base = { campaignId: null };
  const requested = catalogType == null || catalogType === ""
    ? "REGULAR"
    : String(catalogType).trim().toUpperCase();

  if (!["REGULAR", "PREORDER", "ALL"].includes(requested)) {
    const err = new Error("catalogType must be REGULAR, PREORDER, or all");
    err.statusCode = 400;
    throw err;
  }

  if (requested === "REGULAR") {
    return { ...base, catalogType: "REGULAR" };
  }

  const isOwner = sellerId && userId && String(sellerId) === String(userId);
  if (!isOwner) {
    return { ...base, catalogType: "REGULAR" };
  }

  if (requested === "PREORDER") {
    return { ...base, catalogType: "PREORDER" };
  }
  return base;
}

function isRegularMarketplaceListing(listing) {
  return Boolean(
    listing &&
      listing.catalogType !== "PREORDER" &&
      !listing.campaignId
  );
}

function isActiveCampaignRecord(campaign) {
  if (!campaign) return false;
  if (
    campaign.status === "open" &&
    campaign.orderCutoffAt &&
    new Date(campaign.orderCutoffAt) <= new Date()
  ) {
    return false;
  }
  return ACTIVE_CAMPAIGN_STATUSES.includes(campaign.status);
}

async function listingInActiveCampaign(prisma, listing) {
  if (!listing) return false;

  if (listing.campaignId) {
    const campaign = await prisma.preOrderCampaign.findUnique({
      where: { id: listing.campaignId },
      select: { status: true, orderCutoffAt: true },
    });
    return isActiveCampaignRecord(campaign);
  }

  const copies = await prisma.listing.findMany({
    where: {
      sourceListingId: listing.id,
      campaignId: { not: null },
    },
    select: {
      campaign: { select: { status: true, orderCutoffAt: true } },
    },
  });
  return copies.some((copy) => isActiveCampaignRecord(copy.campaign));
}

const ACTIVE_CAMPAIGN_MOVE_ERROR =
  "This item is part of an active pre-order campaign and cannot be moved until the campaign is completed.";
const ACTIVE_CAMPAIGN_DELETE_ERROR =
  "This item is part of an active pre-order campaign and cannot be removed until the campaign is completed.";

module.exports = {
  CATALOG_TYPES,
  parseCatalogType,
  regularMarketplaceWhere,
  catalogListWhere,
  isRegularMarketplaceListing,
  listingInActiveCampaign,
  ACTIVE_CAMPAIGN_MOVE_ERROR,
  ACTIVE_CAMPAIGN_DELETE_ERROR,
};
