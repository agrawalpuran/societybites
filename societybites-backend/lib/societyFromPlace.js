const { assertPlaceAllowedForLaunch } = require("./launchCity");

const PNH_SOCIETY_ID = "prestige-notting-hill";
const INVITE_CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function httpError(statusCode, message, code) {
  const err = new Error(message);
  err.statusCode = statusCode;
  if (code) err.code = code;
  return err;
}

function isPlaceSchemaUnavailable(err) {
  if (!err) return false;
  if (err.code === "P2022") return true;
  const message = String(err.message || "");
  return (
    message.includes("googlePlaceId") ||
    message.includes("Unknown arg") ||
    message.includes("Unknown field")
  );
}

function placeSchemaUnavailableError() {
  return httpError(
    503,
    "Society search is temporarily unavailable.",
    "PLACES_UNAVAILABLE"
  );
}

function cityRequiredError() {
  return httpError(
    400,
    "We couldn't confirm this society's city. Please try a different result.",
    "PLACE_CITY_REQUIRED"
  );
}

function normalizePlaceName(name) {
  return String(name || "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

function isPrestigeNottingHillPlace(
  placeName,
  existingName = "Prestige Notting Hill"
) {
  const google = normalizePlaceName(placeName);
  const existing = normalizePlaceName(existingName);
  if (!google || !existing) return false;
  return google === existing || google.includes(existing) || existing.includes(google);
}

function componentText(component) {
  return String(component?.longText || component?.shortText || "").trim();
}

function findComponent(addressComponents, type) {
  const list = Array.isArray(addressComponents) ? addressComponents : [];
  const match = list.find(
    (item) => Array.isArray(item.types) && item.types.includes(type)
  );
  return componentText(match);
}

function extractAddressParts(addressComponents) {
  const locality =
    findComponent(addressComponents, "locality") ||
    findComponent(addressComponents, "postal_town");
  const district = findComponent(addressComponents, "administrative_area_level_2");
  return {
    city: locality,
    district,
    state: findComponent(addressComponents, "administrative_area_level_1"),
    pincode: findComponent(addressComponents, "postal_code"),
  };
}

function mapPlaceDetails(json) {
  const parts = extractAddressParts(json?.addressComponents);
  const latitude =
    typeof json?.location?.latitude === "number" ? json.location.latitude : null;
  const longitude =
    typeof json?.location?.longitude === "number" ? json.location.longitude : null;

  return {
    placeId: String(json?.id || "").trim(),
    name: String(json?.displayName?.text || "").trim(),
    address: String(json?.formattedAddress || "").trim(),
    city: parts.city,
    district: parts.district,
    state: parts.state,
    pincode: parts.pincode,
    latitude,
    longitude,
  };
}

function mapAutocompleteSuggestions(json) {
  const suggestions = Array.isArray(json?.suggestions) ? json.suggestions : [];
  return suggestions
    .map((item) => {
      const pred = item.placePrediction;
      if (!pred || !pred.placeId) return null;
      const name = String(
        pred.structuredFormat?.mainText?.text || pred.text?.text || ""
      ).trim();
      const address = String(
        pred.structuredFormat?.secondaryText?.text || ""
      ).trim();
      if (!name) return null;
      return {
        placeId: String(pred.placeId).trim(),
        name,
        address,
      };
    })
    .filter(Boolean)
    .slice(0, 8);
}

function generateInviteCode() {
  let code = "";
  for (let i = 0; i < 10; i += 1) {
    code += INVITE_CODE_CHARS.charAt(
      Math.floor(Math.random() * INVITE_CODE_CHARS.length)
    );
  }
  return code;
}

function matchesDatabaseQuery(society, query) {
  const needle = String(query || "").trim().toLowerCase();
  if (needle.length < 2) return false;
  const haystack = [society.name, society.address, society.city, society.state, society.pincode]
    .map((value) => String(value || "").trim().toLowerCase())
    .join(" ");
  return haystack.includes(needle);
}

function publicPlace(place) {
  return {
    placeId: place.placeId,
    name: place.name,
    address: place.address,
    city: place.city,
    state: place.state,
    pincode: place.pincode,
  };
}

async function uniqueInviteCode(prisma) {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const inviteCode = generateInviteCode();
    const existing = await prisma.society.findUnique({ where: { inviteCode } });
    if (!existing) return inviteCode;
  }
  throw httpError(500, "Could not create society. Please try again.");
}

async function matchExistingSociety(prisma, place) {
  if (place.placeId) {
    try {
      const byPlace = await prisma.society.findUnique({
        where: { googlePlaceId: place.placeId },
        include: { blocks: { orderBy: { name: "asc" } } },
      });
      if (byPlace) return byPlace;
    } catch (err) {
      if (!isPlaceSchemaUnavailable(err)) throw err;
    }
  }

  const pnh = await prisma.society.findUnique({
    where: { id: PNH_SOCIETY_ID },
    include: { blocks: { orderBy: { name: "asc" } } },
  });
  if (pnh && isPrestigeNottingHillPlace(place.name, pnh.name)) {
    return pnh;
  }

  return null;
}

function backfillData(existing, place) {
  const data = {};
  if (!existing.googlePlaceId && place.placeId) {
    data.googlePlaceId = place.placeId;
  }
  if (existing.latitude == null && place.latitude != null) {
    data.latitude = place.latitude;
  }
  if (existing.longitude == null && place.longitude != null) {
    data.longitude = place.longitude;
  }
  if (!existing.address && place.address) data.address = place.address;
  if (!existing.state && place.state) data.state = place.state;
  if (!existing.pincode && place.pincode) data.pincode = place.pincode;
  return data;
}

async function backfillIfNeeded(prisma, existing, place) {
  const data = backfillData(existing, place);
  if (Object.keys(data).length === 0) return existing;
  try {
    return await prisma.society.update({
      where: { id: existing.id },
      data,
      include: { blocks: { orderBy: { name: "asc" } } },
    });
  } catch (err) {
    if (isPlaceSchemaUnavailable(err)) return existing;
    throw err;
  }
}

async function createSocietyFromPlace(prisma, place) {
  assertPlaceAllowedForLaunch(place);
  const city = String(place.city || place.district || "").trim();
  if (!city) throw cityRequiredError();
  if (!place.name) {
    throw httpError(400, "We couldn't identify this society.");
  }

  const inviteCode = await uniqueInviteCode(prisma);
  try {
    return await prisma.society.create({
      data: {
        name: place.name,
        city,
        address: place.address || null,
        state: place.state || null,
        pincode: place.pincode || null,
        googlePlaceId: place.placeId,
        latitude: place.latitude,
        longitude: place.longitude,
        inviteCode,
        status: "active",
        unitLabel: "Block",
      },
      include: { blocks: { orderBy: { name: "asc" } } },
    });
  } catch (err) {
    if (isPlaceSchemaUnavailable(err)) {
      throw placeSchemaUnavailableError();
    }
    if (err && err.code === "P2002") {
      try {
        const raced = await prisma.society.findUnique({
          where: { googlePlaceId: place.placeId },
          include: { blocks: { orderBy: { name: "asc" } } },
        });
        if (raced) return raced;
      } catch (lookupErr) {
        if (!isPlaceSchemaUnavailable(lookupErr)) throw lookupErr;
      }
    }
    throw err;
  }
}

async function previewSocietyFromPlace(prisma, place, { persist = false } = {}) {
  if (!place.placeId || !place.name) {
    throw httpError(400, "We couldn't identify this society.");
  }

  let society = await matchExistingSociety(prisma, place);
  if (society) {
    if (persist) {
      society = await backfillIfNeeded(prisma, society, place);
    }
    return { place: publicPlace(place), society, isNew: false };
  }

  if (!place.city && !place.district) throw cityRequiredError();
  assertPlaceAllowedForLaunch(place);
  return { place: publicPlace(place), society: null, isNew: true };
}

async function findOrCreateSocietyFromPlace(prisma, place) {
  const preview = await previewSocietyFromPlace(prisma, place, { persist: true });
  if (preview.society) return preview.society;
  return createSocietyFromPlace(prisma, place);
}

module.exports = {
  PNH_SOCIETY_ID,
  cityRequiredError,
  normalizePlaceName,
  isPrestigeNottingHillPlace,
  extractAddressParts,
  mapPlaceDetails,
  mapAutocompleteSuggestions,
  generateInviteCode,
  matchesDatabaseQuery,
  publicPlace,
  matchExistingSociety,
  backfillData,
  previewSocietyFromPlace,
  findOrCreateSocietyFromPlace,
  createSocietyFromPlace,
};
