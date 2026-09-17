const { canonicalCityKey } = require("./launchCity");
const { isValidSocietyLocation } = require("./geoDistance");

function isMissingCity(city) {
  return !String(city || "").trim();
}

function auditSocietyLocations(societies) {
  const rows = Array.isArray(societies) ? societies : [];
  const missingLatitude = [];
  const missingLongitude = [];
  const missingBoth = [];
  const missingOrInvalidCity = [];
  const withValidCoordinates = [];
  const cityDistribution = {};
  const canonicalCityDistribution = {};

  for (const society of rows) {
    const lat = society.latitude;
    const lng = society.longitude;
    const hasLat = lat != null && lat !== "" && Number.isFinite(Number(lat));
    const hasLng = lng != null && lng !== "" && Number.isFinite(Number(lng));
    const validPair = isValidSocietyLocation({
      latitude: hasLat ? Number(lat) : null,
      longitude: hasLng ? Number(lng) : null,
    });

    if (!hasLat && !hasLng) missingBoth.push(society);
    if (!hasLat) missingLatitude.push(society);
    if (!hasLng) missingLongitude.push(society);
    if (validPair) withValidCoordinates.push(society);
    if (isMissingCity(society.city)) missingOrInvalidCity.push(society);

    const rawCity = String(society.city || "").trim() || "(missing)";
    cityDistribution[rawCity] = (cityDistribution[rawCity] || 0) + 1;
    const canonical = canonicalCityKey(society.city) || "(missing)";
    canonicalCityDistribution[canonical] = (canonicalCityDistribution[canonical] || 0) + 1;
  }

  return {
    totalSocieties: rows.length,
    withValidLatitudeAndLongitude: withValidCoordinates.length,
    missingLatitude: missingLatitude.length,
    missingLongitude: missingLongitude.length,
    missingBoth: missingBoth.length,
    missingOrInvalidCity: missingOrInvalidCity.length,
    cityDistribution,
    canonicalCityDistribution,
    missingCoordinateIds: {
      latitude: missingLatitude.map((s) => s.id),
      longitude: missingLongitude.map((s) => s.id),
      both: missingBoth.map((s) => ({ id: s.id, name: s.name, city: s.city })),
    },
  };
}

async function auditSocietyLocationsFromDb(prismaClient) {
  const societies = await prismaClient.society.findMany({
    select: {
      id: true,
      name: true,
      city: true,
      address: true,
      state: true,
      pincode: true,
      googlePlaceId: true,
      latitude: true,
      longitude: true,
    },
    orderBy: { name: "asc" },
  });
  return {
    ...auditSocietyLocations(societies),
    societies,
  };
}

module.exports = {
  isMissingCity,
  auditSocietyLocations,
  auditSocietyLocationsFromDb,
};
