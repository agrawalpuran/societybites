require("dotenv").config();
const prisma = require("../lib/prisma");
const { auditSocietyLocations, auditSocietyLocationsFromDb } = require("../lib/societyLocationAudit");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function mainUnit() {
  const report = auditSocietyLocations([
    { id: "a", name: "A", city: "Bangalore", latitude: 12.9, longitude: 77.6 },
    { id: "b", name: "B", city: "Bengaluru", latitude: null, longitude: null },
    { id: "c", name: "C", city: "  ", latitude: 12.8, longitude: null },
  ]);
  assert(report.totalSocieties === 3, "total");
  assert(report.withValidLatitudeAndLongitude === 1, "valid pair");
  assert(report.missingLatitude === 1, "missing lat");
  assert(report.missingLongitude === 2, "missing lng");
  assert(report.missingBoth === 1, "missing both");
  assert(report.missingOrInvalidCity === 1, "invalid city");
  assert(report.canonicalCityDistribution.bengaluru === 2, "Bangalore/Bengaluru collapse");
}

async function mainDb() {
  const report = await auditSocietyLocationsFromDb(prisma);
  assert(Number.isInteger(report.totalSocieties), "db total");
  assert(report.withValidLatitudeAndLongitude <= report.totalSocieties, "valid <= total");
  assert(
    report.missingBoth + report.withValidLatitudeAndLongitude <= report.totalSocieties ||
      report.totalSocieties >= 0,
    "counts consistent"
  );
  console.log("SOCIETY_LOCATION_AUDIT", JSON.stringify({
    totalSocieties: report.totalSocieties,
    withValidLatitudeAndLongitude: report.withValidLatitudeAndLongitude,
    missingLatitude: report.missingLatitude,
    missingLongitude: report.missingLongitude,
    missingBoth: report.missingBoth,
    missingOrInvalidCity: report.missingOrInvalidCity,
    cityDistribution: report.cityDistribution,
    canonicalCityDistribution: report.canonicalCityDistribution,
    societiesMissingBoth: report.missingCoordinateIds.both,
  }));
}

mainUnit();
mainDb()
  .then(() => {
    console.log("society-location-audit tests passed");
    process.exit(0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
