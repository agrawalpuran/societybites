const EARTH_RADIUS_KM = 6371;

function toRadians(degrees) {
  return (degrees * Math.PI) / 180;
}

function isValidCoordinate(value, min, max) {
  return typeof value === "number" && Number.isFinite(value) && value >= min && value <= max;
}

function isValidSocietyLocation(location) {
  if (!location) return false;
  return (
    isValidCoordinate(location.latitude, -90, 90) &&
    isValidCoordinate(location.longitude, -180, 180)
  );
}

/**
 * Great-circle distance in kilometres (Haversine).
 * Returns null when either point is missing or invalid.
 */
function distanceKmBetweenCoordinates(a, b) {
  if (!isValidSocietyLocation(a) || !isValidSocietyLocation(b)) return null;

  const lat1 = toRadians(a.latitude);
  const lat2 = toRadians(b.latitude);
  const dLat = lat2 - lat1;
  const dLng = toRadians(b.longitude - a.longitude);

  const hav =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;

  return 2 * EARTH_RADIUS_KM * Math.asin(Math.min(1, Math.sqrt(hav)));
}

module.exports = {
  EARTH_RADIUS_KM,
  isValidSocietyLocation,
  distanceKmBetweenCoordinates,
};
