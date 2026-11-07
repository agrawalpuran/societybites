const prisma = require("./prisma");
const { serializeListing } = require("../utils/listingSerializer");
const { expireDueListings, DISCOVERABLE_STATUSES } = require("../utils/listingExpiry");
const { attachRecurringAvailability } = require("./recurringAvailability");
const { sortSellerCatalogListings } = require("./listingCatalogOrder");
const { withoutAutomatedTestListings } = require("./testListingNames");
const RESERVED_SLUGS = new Set([
  "www",
  "app",
  "api",
  "admin",
  "kitchen",
  "s",
  "c",
  "l",
  "seller",
  "login",
  "auth",
  "static",
  "assets",
]);

const SLUG_PATTERN = /^[a-z0-9](?:[a-z0-9-]{0,28}[a-z0-9])?$/;
const ACCENT_PATTERN = /^#[0-9A-Fa-f]{6}$/;
const DEFAULT_ACCENT = "#0E5A47";

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function normalizeSlug(raw) {
  if (raw == null) return "";
  return String(raw).trim().toLowerCase();
}

function assertValidStorefrontSlug(slug) {
  const normalized = normalizeSlug(slug);
  if (!normalized || normalized.length < 2) {
    throw httpError(400, "Kitchen link must be at least 2 characters");
  }
  if (!SLUG_PATTERN.test(normalized)) {
    throw httpError(400, "Kitchen link may only use lowercase letters, numbers, and hyphens");
  }
  if (RESERVED_SLUGS.has(normalized)) {
    throw httpError(400, "This kitchen link is reserved");
  }
  return normalized;
}

function parseAccentColor(raw) {
  if (raw == null || raw === "") return null;
  const value = String(raw).trim();
  if (!ACCENT_PATTERN.test(value)) {
    throw httpError(400, "Accent color must be a #RRGGBB hex value");
  }
  return value.toUpperCase();
}

function parseOptionalUrl(raw) {
  if (raw == null || raw === "") return null;
  const value = String(raw).trim();
  if (value.length > 500) throw httpError(400, "Banner URL is too long");
  if (!/^https:\/\//i.test(value)) {
    throw httpError(400, "Banner URL must use https");
  }
  return value;
}

function parseOptionalTagline(raw) {
  if (raw == null || raw === "") return null;
  const value = String(raw).trim();
  if (value.length > 120) throw httpError(400, "Tagline is too long");
  return value;
}

const ACTIVE_REGULAR_LISTING_WHERE = {
  status: { in: DISCOVERABLE_STATUSES },
  campaignId: null,
  catalogType: "REGULAR",
};

async function getKitchenBySlug(slugInput) {
  const slug = normalizeSlug(slugInput);
  if (!slug) throw httpError(404, "Kitchen not found");

  const seller = await prisma.user.findFirst({
    where: { storefrontSlug: slug },
    include: {
      society: { select: { id: true, name: true, city: true } },
      flat: { select: { block: true, flatNumber: true } },
      listings: {
        where: ACTIVE_REGULAR_LISTING_WHERE,
        include: {
          reviews: { select: { rating: true } },
          society: { select: { name: true } },
        },
      },
    },
  });

  if (!seller) throw httpError(404, "Kitchen not found");
  if (seller.suspended) throw httpError(404, "Kitchen not found");
  if (!["seller", "super_admin"].includes(seller.role || "")) {
    throw httpError(404, "Kitchen not found");
  }

  await expireDueListings(prisma, { sellerId: seller.id });

  const sorted = sortSellerCatalogListings(seller.listings || []);
  const withRecurring = await attachRecurringAvailability(
    prisma,
    withoutAutomatedTestListings(sorted)
  );

  const listings = withRecurring.map((listing) =>
    serializeListing(listing, { seller, viewerUserId: null })
  );

  const categories = [
    ...new Set(
      listings
        .flatMap((item) => item.categories || [])
        .filter(Boolean)
    ),
  ];

  const societyName = (seller.society && seller.society.name) || null;
  const displayName =
    (seller.upiDisplayName && seller.upiDisplayName.trim()) ||
    (seller.name && seller.name.trim()) ||
    "Kitchen";

  return {
    slug,
    branding: {
      accentColor: seller.storefrontAccentColor || DEFAULT_ACCENT,
      bannerUrl: seller.storefrontBannerUrl || null,
      tagline: seller.storefrontTagline || null,
    },
    seller: {
      id: seller.id,
      name: displayName,
      legalName: seller.name || null,
      societyName,
      societyCity: (seller.society && seller.society.city) || null,
      profilePhotoUrl: seller.profilePhotoUrl || null,
      categories,
    },
    listings,
  };
}

async function parseStorefrontWrite(body, { partial = false } = {}) {
  const source = body && typeof body === "object" ? body : {};
  const data = {};

  if (!partial || source.storefrontSlug !== undefined) {
    if (source.storefrontSlug === null || source.storefrontSlug === "") {
      data.storefrontSlug = null;
    } else {
      data.storefrontSlug = assertValidStorefrontSlug(source.storefrontSlug);
    }
  }
  if (!partial || source.storefrontAccentColor !== undefined) {
    data.storefrontAccentColor = parseAccentColor(source.storefrontAccentColor);
  }
  if (!partial || source.storefrontBannerUrl !== undefined) {
    data.storefrontBannerUrl = parseOptionalUrl(source.storefrontBannerUrl);
  }
  if (!partial || source.storefrontTagline !== undefined) {
    data.storefrontTagline = parseOptionalTagline(source.storefrontTagline);
  }

  return data;
}

module.exports = {
  RESERVED_SLUGS,
  DEFAULT_ACCENT,
  normalizeSlug,
  assertValidStorefrontSlug,
  getKitchenBySlug,
  parseStorefrontWrite,
};
