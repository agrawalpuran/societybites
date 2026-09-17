require("dotenv").config();
const prisma = require("../lib/prisma");
const { auditSocietyLocationsFromDb } = require("../lib/societyLocationAudit");

auditSocietyLocationsFromDb(prisma)
  .then((report) => {
    const withCoords = report.societies
      .filter((s) => s.latitude != null && s.longitude != null)
      .map((s) => ({ id: s.id, name: s.name, city: s.city }));
    console.log(JSON.stringify({
      totals: {
        totalSocieties: report.totalSocieties,
        withValidLatitudeAndLongitude: report.withValidLatitudeAndLongitude,
        missingLatitude: report.missingLatitude,
        missingLongitude: report.missingLongitude,
        missingBoth: report.missingBoth,
        missingOrInvalidCity: report.missingOrInvalidCity,
      },
      cityDistribution: report.cityDistribution,
      canonicalCityDistribution: report.canonicalCityDistribution,
      societiesWithCoordinates: withCoords,
      societiesMissingCoordinates: report.missingCoordinateIds.both,
    }, null, 2));
  })
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
