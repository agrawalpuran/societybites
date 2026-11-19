/**
 * Separate local PostgreSQL check for coupon-row rollback.
 * The foundation database has no Coupon table, so this file cannot create a
 * coupon row there. It prints COUPON_TABLE_ABSENT_ON_FOUNDATION and exits
 * without writing. When Coupon exists on the same guarded database, it creates
 * an assigned coupon inside a transaction and rolls that transaction back.
 * Not part of npm test. Does not apply a migration and does not read .env.
 */
const crypto = require("crypto");
const { PrismaClient } = require("@prisma/client");
const { withPrismaPoolParams } = require("../lib/prismaPool");
const { createAssignedCoupon } = require("../lib/coupons");

const REQUIRED_HOST = "127.0.0.1";
const REQUIRED_PORT = "5432";
const REQUIRED_DATABASE = "societybites_incentive_foundation";
const PREFIX = `p2ec${crypto.randomBytes(6).toString("hex")}`;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function assertSafeUrl(value) {
  if (!value || typeof value !== "string") throw new Error("DATABASE_URL must be set before this test starts");
  const lowered = value.toLowerCase();
  if (lowered.includes("supabase") || lowered.includes("pooler.supabase")) {
    throw new Error("DATABASE_URL must not point at Supabase");
  }
  const parsed = new URL(value);
  const database = decodeURIComponent(parsed.pathname.replace(/^\//, ""));
  if (parsed.hostname !== REQUIRED_HOST) throw new Error(`host must be ${REQUIRED_HOST}`);
  if ((parsed.port || REQUIRED_PORT) !== REQUIRED_PORT) throw new Error(`port must be ${REQUIRED_PORT}`);
  if (database !== REQUIRED_DATABASE) throw new Error(`database must be ${REQUIRED_DATABASE}`);
}

async function main() {
  assertSafeUrl(process.env.DATABASE_URL);
  const bounded = new URL(withPrismaPoolParams(process.env.DATABASE_URL));
  bounded.searchParams.set("connection_limit", "1");
  const prisma = new PrismaClient({ datasources: { db: { url: bounded.toString() } } });
  try {
    const couponTable = await prisma.$queryRaw`SELECT to_regclass('"Coupon"')::text AS name`;
    if (!couponTable[0].name) {
      console.log("COUPON_TABLE_ABSENT_ON_FOUNDATION");
      console.log("Coupon, CouponEligibleUser, reward, and budget rollback for a failed coupon write is covered by tests/incentive-rewards-pg.integration.js for the reward and budget. A Coupon row cannot be created on this database.");
      return;
    }
    const code = `SB${PREFIX}`.slice(0, 24);
    const before = await prisma.coupon.count({ where: { code } });
    await prisma.$transaction(async (tx) => {
      await createAssignedCoupon(tx, {
        code,
        name: "SocietyEats reward",
        discountType: "FIXED",
        discountValue: 20,
        minimumOrderValue: 0,
        validFrom: new Date("2026-11-17T00:00:00.000Z"),
        validUntil: new Date("2026-12-17T00:00:00.000Z"),
        totalUsageLimit: 1,
        usagePerBuyerLimit: 1,
        audienceType: "SELECTED_USERS",
        userIds: [`${PREFIX}-user`],
        status: "ACTIVE",
      });
      throw new Error("ROLLBACK_COUPON");
    }).catch((error) => {
      if (error.message !== "ROLLBACK_COUPON") throw error;
    });
    assert(await prisma.coupon.count({ where: { code } }) === before, "a rolled-back coupon remains");
    console.log("incentive rewards coupon rollback ok");
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
