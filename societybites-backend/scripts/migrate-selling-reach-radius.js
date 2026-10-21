/**
 * One-time idempotent migration: NEARBY/EXTENDED -> BEYOND_SOCIETY + sellingReachRadiusKm.
 * Run after prisma migrate deploy (also invoked from ensure-db-migrations.js).
 */
require("dotenv").config();
const prisma = require("../lib/prisma");
const { canonicalCityKey } = require("../lib/launchCity");
const {
  SELLING_REACH_LEVELS,
  maxSellerRadiusKmFromConfig,
  DEFAULT_MAX_SELLER_RADIUS_KM,
} = require("../lib/sellingReach");

function clampRadius(km, maxKm) {
  const max = Math.max(1, Math.round(maxKm));
  const value = Math.round(Number(km));
  if (!Number.isFinite(value)) return Math.min(5, max);
  return Math.min(max, Math.max(1, value));
}

async function main() {
  const users = await prisma.user.findMany({
    where: {
      sellingReachLevel: {
        in: [SELLING_REACH_LEVELS.NEARBY, SELLING_REACH_LEVELS.EXTENDED],
      },
    },
    include: { society: { select: { city: true } } },
  });

  let updated = 0;
  for (const user of users) {
    if (user.sellingReachRadiusKm != null) continue;
    const cityKey = canonicalCityKey(user.society && user.society.city);
    let config = null;
    if (cityKey) {
      config = await prisma.cityReachConfig.findUnique({ where: { cityKey } });
    }
    const maxKm = config
      ? maxSellerRadiusKmFromConfig(config)
      : DEFAULT_MAX_SELLER_RADIUS_KM;
    const legacyKm =
      user.sellingReachLevel === SELLING_REACH_LEVELS.NEARBY
        ? config && config.nearbyRadiusKm
        : config && config.extendedRadiusKm;
    const radius = clampRadius(legacyKm ?? maxKm, maxKm);
    await prisma.user.update({
      where: { id: user.id },
      data: {
        sellingReachLevel: SELLING_REACH_LEVELS.BEYOND_SOCIETY,
        sellingReachRadiusKm: radius,
      },
    });
    updated += 1;
  }

  console.log(`[migrate-selling-reach-radius] updated ${updated} seller(s)`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
