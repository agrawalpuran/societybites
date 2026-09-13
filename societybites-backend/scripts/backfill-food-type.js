require("dotenv").config();
const prisma = require("../lib/prisma");
const { inferFoodTypeFromTags } = require("../utils/foodType");

async function main() {
  const listings = await prisma.listing.findMany({
    select: { id: true, tags: true, foodType: true },
  });

  let classifiedVeg = 0;
  let classifiedNonVeg = 0;
  let skippedAlreadySet = 0;
  let leftNull = 0;

  for (const listing of listings) {
    if (listing.foodType === "VEG" || listing.foodType === "NON_VEG") {
      skippedAlreadySet += 1;
      continue;
    }
    const inferred = inferFoodTypeFromTags(listing.tags);
    if (!inferred) {
      leftNull += 1;
      continue;
    }
    await prisma.listing.update({
      where: { id: listing.id },
      data: { foodType: inferred },
    });
    if (inferred === "VEG") classifiedVeg += 1;
    else classifiedNonVeg += 1;
  }

  const remainingNull = await prisma.listing.count({ where: { foodType: null } });
  const vegCount = await prisma.listing.count({ where: { foodType: "VEG" } });
  const nonVegCount = await prisma.listing.count({
    where: { foodType: "NON_VEG" },
  });

  console.log(
    JSON.stringify(
      {
        total: listings.length,
        newlyClassifiedVeg: classifiedVeg,
        newlyClassifiedNonVeg: classifiedNonVeg,
        newlyClassified: classifiedVeg + classifiedNonVeg,
        alreadySetSkipped: skippedAlreadySet,
        leftNullThisRun: leftNull,
        currentVeg: vegCount,
        currentNonVeg: nonVegCount,
        currentNull: remainingNull,
      },
      null,
      2
    )
  );
}

main()
  .catch((err) => {
    console.error(err.message || err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
