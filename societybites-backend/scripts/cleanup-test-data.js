/**
 * Removes rows created by backend tests that ran against the live database.
 * Seed societies and the seed buyer/seller are never deleted.
 *
 *   node scripts/cleanup-test-data.js
 *   node scripts/cleanup-test-data.js --apply
 */
require("dotenv").config();
const prisma = require("../lib/prisma");

const PROTECTED_PHONES = new Set(["+919845154070", "+919901844776"]);
const PROTECTED_SOCIETY_IDS = new Set([
  "prestige-notting-hill",
  "brigade-gateway",
  "sobha-dream-acres",
]);

const SOCIETY_NAME =
  /^(Guest BLR |Guest Pune |P4B (Buyer|NearIn|NearOut|ExtOut|NoCoord|Pune) |PO (Buyer|Near|Mid|Far) |P5 (Buyer|Near|Far|NoCoord|Pune) |Catalog (buyer|nearby) )/;

const USER_NAMES = new Set([
  "Guest Nearby Kitchen",
  "Guest Extended Kitchen",
  "Guest My Society Kitchen",
  "Guest Empty Kitchen",
  "Guest Preorder Kitchen",
  "Guest Pune Kitchen",
  "Guest Buyer",
  "Issue Buyer",
  "Issue Seller",
  "Issue Admin",
  "Reach Test Admin",
  "FSSAI Seller",
  "FSSAI Buyer",
  "FSSAI Admin",
  "Terms Buyer",
  "Delete Me",
  "Other Bulk Seller",
  "Bulk Buyer Only",
]);

const FIXED_TEST_PHONES = [
  "+919800000091",
  "+919800000093",
  "+919800000094",
  "+919800000095",
  "+919800000181",
  "+919800000182",
  "+919800000201",
  "+919800000202",
  "+919111000001",
  "+919111000002",
  "+919111000003",
  "+919111000018",
  "+919111000019",
  "+919111000028",
  "+919111000029",
  "+919111000039",
  "+919111000070",
  "+919111000071",
];

const { isAutomatedTestListingName } = require("../lib/testListingNames");

const CITY_KEYS = ["phase4bville", "phase5ville", "phasepreorderville"];

async function collect() {
  const societies = await prisma.society.findMany({
    where: { name: { not: "" } },
    select: { id: true, name: true, city: true, inviteCode: true },
  });
  const testSocieties = societies.filter(
    (society) =>
      !PROTECTED_SOCIETY_IDS.has(society.id) && SOCIETY_NAME.test(society.name)
  );
  const societyIds = testSocieties.map((society) => society.id);

  const users = await prisma.user.findMany({
    select: { id: true, name: true, phone: true, role: true, societyId: true },
  });
  const testUsers = users.filter((user) => {
    if (PROTECTED_PHONES.has(user.phone)) return false;
    if (user.societyId && societyIds.includes(user.societyId)) return true;
    if (user.name && USER_NAMES.has(user.name)) return true;
    if (FIXED_TEST_PHONES.includes(user.phone)) return true;
    return false;
  });
  const userIds = testUsers.map((user) => user.id);

  const listings = await prisma.listing.findMany({
    select: { id: true, name: true, sellerId: true, societyId: true },
  });
  const testListings = listings.filter(
    (listing) =>
      societyIds.includes(listing.societyId) ||
      userIds.includes(listing.sellerId) ||
      isAutomatedTestListingName(listing.name)
  );
  const listingIds = testListings.map((listing) => listing.id);

  const campaigns = await prisma.preOrderCampaign.findMany({
    select: { id: true, title: true, sellerId: true, societyId: true },
  });
  const testCampaigns = campaigns.filter(
    (campaign) =>
      societyIds.includes(campaign.societyId) ||
      userIds.includes(campaign.sellerId) ||
      campaign.title === "Guest Campaign"
  );
  const campaignIds = testCampaigns.map((campaign) => campaign.id);

  const orders = await prisma.order.findMany({
    select: { id: true, buyerId: true, societyId: true, campaignId: true },
  });
  const orderItems = listingIds.length
    ? await prisma.orderItem.findMany({
        where: { listingId: { in: listingIds } },
        select: { orderId: true },
      })
    : [];
  const orderIdsFromItems = new Set(orderItems.map((item) => item.orderId));
  const testOrders = orders.filter(
    (order) =>
      userIds.includes(order.buyerId) ||
      societyIds.includes(order.societyId) ||
      (order.campaignId && campaignIds.includes(order.campaignId)) ||
      orderIdsFromItems.has(order.id)
  );

  const cityConfigs = await prisma.cityReachConfig.findMany({
    select: { cityKey: true, displayName: true },
  });
  const testCities = cityConfigs.filter(
    (city) =>
      CITY_KEYS.includes(city.cityKey) ||
      city.cityKey.startsWith("catalogville") ||
      /^(Phase4B Ville|Phase5 Ville|CatalogVille )/.test(city.displayName)
  );

  return {
    testSocieties,
    testUsers,
    testListings,
    testCampaigns,
    testOrders,
    testCities,
    societyIds,
    userIds,
    listingIds,
    campaignIds,
    orderIds: testOrders.map((order) => order.id),
  };
}

function printPlan(plan) {
  console.log(`societies ${plan.testSocieties.length}`);
  for (const society of plan.testSocieties) {
    console.log(`  society: ${society.name} | ${society.city} | ${society.inviteCode}`);
  }
  console.log(`users ${plan.testUsers.length}`);
  const byName = {};
  for (const user of plan.testUsers) {
    const key = user.name || "(no name)";
    byName[key] = (byName[key] || 0) + 1;
  }
  for (const [name, count] of Object.entries(byName).sort()) {
    console.log(`  user: ${count} x ${name}`);
  }
  console.log(`listings ${plan.testListings.length}`);
  const byListing = {};
  for (const listing of plan.testListings) {
    const key = listing.name.replace(/\d{6,}/g, "#");
    byListing[key] = (byListing[key] || 0) + 1;
  }
  for (const [name, count] of Object.entries(byListing).sort()) {
    console.log(`  listing: ${count} x ${name}`);
  }
  console.log(`campaigns ${plan.testCampaigns.length}`);
  console.log(`orders ${plan.testOrders.length}`);
  console.log(`city configs ${plan.testCities.length}`);
  for (const city of plan.testCities) {
    console.log(`  city: ${city.cityKey} | ${city.displayName}`);
  }
}

async function apply(plan) {
  const { userIds, societyIds, listingIds, campaignIds, orderIds } = plan;
  if (orderIds.length) {
    await prisma.message.deleteMany({ where: { orderId: { in: orderIds } } });
    await prisma.review.deleteMany({ where: { orderId: { in: orderIds } } });
    await prisma.orderItem.deleteMany({ where: { orderId: { in: orderIds } } });
    await prisma.order.deleteMany({ where: { id: { in: orderIds } } });
  }
  if (listingIds.length) {
    await prisma.review.deleteMany({ where: { listingId: { in: listingIds } } });
    await prisma.orderItem.deleteMany({ where: { listingId: { in: listingIds } } });
    await prisma.listing.updateMany({
      where: { sourceListingId: { in: listingIds } },
      data: { sourceListingId: null },
    });
    await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
  }
  if (campaignIds.length) {
    await prisma.preOrderCampaign.deleteMany({ where: { id: { in: campaignIds } } });
  }
  if (userIds.length) {
    await prisma.sellerTermsAcceptance.deleteMany({ where: { userId: { in: userIds } } });
    await prisma.deviceToken.deleteMany({ where: { userId: { in: userIds } } });
    await prisma.refreshToken.deleteMany({ where: { userId: { in: userIds } } });
    await prisma.issueReport.deleteMany({ where: { userId: { in: userIds } } });
    await prisma.auditLog.deleteMany({ where: { adminId: { in: userIds } } });
    await prisma.message.deleteMany({ where: { senderId: { in: userIds } } });
    await prisma.review.deleteMany({ where: { reviewerId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
  }
  if (societyIds.length) {
    await prisma.block.deleteMany({ where: { societyId: { in: societyIds } } });
    await prisma.flat.deleteMany({ where: { societyId: { in: societyIds } } });
    await prisma.society.deleteMany({ where: { id: { in: societyIds } } });
  }
  if (plan.testCities.length) {
    await prisma.cityReachConfig.deleteMany({
      where: { cityKey: { in: plan.testCities.map((city) => city.cityKey) } },
    });
  }
}

async function main() {
  const plan = await collect();
  printPlan(plan);
  if (!process.argv.includes("--apply")) {
    console.log("dry run only");
    return;
  }
  await apply(plan);
  const after = await collect();
  console.log(
    `remaining societies ${after.testSocieties.length} users ${after.testUsers.length} listings ${after.testListings.length}`
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
