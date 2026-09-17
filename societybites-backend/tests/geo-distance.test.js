const {
  distanceKmBetweenCoordinates,
  isValidSocietyLocation,
} = require("../lib/geoDistance");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function almostEqual(actual, expected, toleranceKm) {
  return Number.isFinite(actual) && Math.abs(actual - expected) <= toleranceKm;
}

function main() {
  assert(!isValidSocietyLocation(null), "null location invalid");
  assert(!isValidSocietyLocation({ latitude: 12.9 }), "lng required");
  assert(!isValidSocietyLocation({ latitude: 91, longitude: 77 }), "lat range");
  assert(isValidSocietyLocation({ latitude: 12.9716, longitude: 77.5946 }), "Bengaluru valid");

  const same = distanceKmBetweenCoordinates(
    { latitude: 12.97, longitude: 77.59 },
    { latitude: 12.97, longitude: 77.59 }
  );
  assert(same === 0, `same point should be 0 km, got ${same}`);

  // Prestige Notting Hill-ish Bannerghatta vs MG Road (~11–14 km).
  const bannerghattaToMg = distanceKmBetweenCoordinates(
    { latitude: 12.889, longitude: 77.597 },
    { latitude: 12.975, longitude: 77.606 }
  );
  assert(
    almostEqual(bannerghattaToMg, 9.6, 1.5),
    `Bannerghatta–MG expected ~9.6 km, got ${bannerghattaToMg}`
  );

  // Known pair: Bengaluru (12.9716, 77.5946) to roughly Whitefield (~16–18 km).
  const whitefield = distanceKmBetweenCoordinates(
    { latitude: 12.9716, longitude: 77.5946 },
    { latitude: 12.9698, longitude: 77.7499 }
  );
  assert(
    almostEqual(whitefield, 16.8, 2),
    `Whitefield expected ~16.8 km, got ${whitefield}`
  );

  assert(
    distanceKmBetweenCoordinates({ latitude: 12.97, longitude: 77.59 }, { latitude: null, longitude: 77.6 }) ==
      null,
    "missing counterpart returns null"
  );

  console.log("geo-distance tests passed");
}

main();
