const { PrismaClient } = require("@prisma/client");

const prisma = new PrismaClient();

const SOCIETY_ID = "prestige-notting-hill";
const BUYER_PHONE = "+919845154070";
const SELLER_PHONE = "+919901844776";

const LISTING_IDS = {
  dal: "seed-listing-dal-makhani",
  chapati: "seed-listing-chapati",
  biryani: "seed-listing-biryani",
  paneer: "seed-listing-paneer-masala",
  lemonRice: "seed-listing-lemon-rice",
};

async function resetTestData(sellerId, buyerId) {
  const orders = await prisma.order.findMany({
    where: { buyerId },
    select: { id: true },
  });

  for (const order of orders) {
    await prisma.review.deleteMany({ where: { orderId: order.id } });
    await prisma.orderItem.deleteMany({ where: { orderId: order.id } });
    await prisma.order.delete({ where: { id: order.id } });
  }

  await prisma.review.deleteMany({ where: { listing: { sellerId } } });
  await prisma.orderItem.deleteMany({ where: { listing: { sellerId } } });
  await prisma.listing.deleteMany({ where: { sellerId } });
}

async function ensureSociety({ id, name, city, inviteCode, unitLabel, blockNames }) {
  const society = await prisma.society.upsert({
    where: { id },
    update: { name, city, inviteCode, unitLabel, status: "active" },
    create: {
      id,
      name,
      city,
      inviteCode,
      unitLabel,
      status: "active",
    },
  });

  for (const blockName of blockNames) {
    const existing = await prisma.block.findFirst({
      where: { societyId: society.id, name: blockName },
    });
    if (!existing) {
      await prisma.block.create({
        data: { societyId: society.id, name: blockName },
      });
    }
  }

  return society;
}

async function main() {
  const pickupTime = new Date();
  pickupTime.setHours(19, 0, 0, 0);

  await ensureSociety({
    id: SOCIETY_ID,
    name: "Prestige Notting Hill",
    city: "Bangalore",
    inviteCode: "PRESTIGE2026",
    unitLabel: "Block",
    blockNames: ["A", "B", "C", "D", "E"],
  });

  await ensureSociety({
    id: "brigade-gateway",
    name: "Brigade Gateway",
    city: "Bangalore",
    inviteCode: "BRIGADE2026",
    unitLabel: "Wing",
    blockNames: ["East", "West", "North"],
  });

  await ensureSociety({
    id: "sobha-dream-acres",
    name: "Sobha Dream Acres",
    city: "Bangalore",
    inviteCode: "SOBHA2026",
    unitLabel: "Block",
    blockNames: ["A", "B", "C", "D"],
  });

  const flat3062 = await prisma.flat.upsert({
    where: {
      societyId_flatNumber: { societyId: SOCIETY_ID, flatNumber: "3062" },
    },
    update: { block: "C", floor: 6, unit: "2" },
    create: {
      societyId: SOCIETY_ID,
      flatNumber: "3062",
      block: "C",
      floor: 6,
      unit: "2",
    },
  });

  const seller = await prisma.user.upsert({
    where: { phone: SELLER_PHONE },
    update: {
      name: "Anita Sharma",
      role: "seller",
      societyId: SOCIETY_ID,
      flatId: flat3062.id,
      upiId: "anita.sharma@oksbi",
      upiDisplayName: "Anita Sharma",
      paymentEnabled: true,
    },
    create: {
      phone: SELLER_PHONE,
      name: "Anita Sharma",
      role: "seller",
      societyId: SOCIETY_ID,
      flatId: flat3062.id,
      upiId: "anita.sharma@oksbi",
      upiDisplayName: "Anita Sharma",
      paymentEnabled: true,
    },
  });

  const buyer = await prisma.user.upsert({
    where: { phone: BUYER_PHONE },
    update: {
      name: "Rahul Mehta",
      role: "buyer",
      societyId: SOCIETY_ID,
      flatId: flat3062.id,
    },
    create: {
      phone: BUYER_PHONE,
      name: "Rahul Mehta",
      role: "buyer",
      societyId: SOCIETY_ID,
      flatId: flat3062.id,
    },
  });

  await resetTestData(seller.id, buyer.id);

  const listings = [
    {
      id: LISTING_IDS.dal,
      name: "Homemade Dal Makhani",
      description:
        "Slow-cooked black lentils with butter and cream. Served with a portion of jeera rice.",
      price: 180,
      quantity: 6,
      imageUrl: "/uploads/dal-makhani.jpg",
      category: "Dinner",
      tags: ["Homestyle", "North Indian"],
    },
    {
      id: LISTING_IDS.chapati,
      name: "Soft Whole Wheat Chapati (Set of 4)",
      description:
        "Freshly rolled and roasted on tawa. Perfect companion for any curry.",
      price: 80,
      quantity: 10,
      imageUrl: "/uploads/chapati.jpg",
      category: "Breakfast",
      tags: ["Fresh", "Healthy"],
    },
    {
      id: LISTING_IDS.biryani,
      name: "Hyderabadi Chicken Biryani",
      description:
        "Aromatic basmati rice layered with spiced chicken, fried onions, and mint.",
      price: 220,
      quantity: 4,
      imageUrl: "/uploads/chicken-biryani.jpg",
      category: "Dinner",
      tags: ["Spicy", "Non-Veg"],
    },
    {
      id: LISTING_IDS.paneer,
      name: "Paneer Butter Masala",
      description:
        "Cottage cheese cubes in a rich tomato-butter gravy. Medium spice.",
      price: 200,
      quantity: 5,
      imageUrl: "/uploads/paneer-butter-masala.jpg",
      category: "Lunch",
      tags: ["Veg", "North Indian"],
    },
    {
      id: LISTING_IDS.lemonRice,
      name: "South Indian Lemon Rice",
      description:
        "Tangy tempered rice with peanuts, curry leaves, and a hint of turmeric.",
      price: 120,
      quantity: 3,
      imageUrl: "/uploads/lemon-rice.jpg",
      category: "Lunch",
      tags: ["South Indian", "Light"],
    },
  ];

  for (const item of listings) {
    await prisma.listing.create({
      data: {
        id: item.id,
        sellerId: seller.id,
        societyId: SOCIETY_ID,
        name: item.name,
        description: item.description,
        price: item.price,
        quantity: item.quantity,
        availableAt: pickupTime,
        pickupLocation: "My Home (Verified)",
        status: "active",
        imageUrl: item.imageUrl,
        category: item.category,
        tags: item.tags,
      },
    });
  }

  await prisma.appSetting.upsert({
    where: { key: "platform_fee" },
    update: { value: "0" },
    create: { key: "platform_fee", value: "0" },
  });

  const pastOrderDate = new Date();
  pastOrderDate.setDate(pastOrderDate.getDate() - 5);

  const completedOrder = await prisma.order.create({
    data: {
      orderNumber: "SB-SEED01",
      buyerId: buyer.id,
      societyId: SOCIETY_ID,
      status: "completed",
      paymentMethod: "upi",
      subtotal: 180,
      communityFee: 0,
      total: 180,
      createdAt: pastOrderDate,
      items: {
        create: {
          listingId: LISTING_IDS.dal,
          quantity: 1,
          unitPrice: 180,
        },
      },
    },
  });

  await prisma.review.create({
    data: {
      orderId: completedOrder.id,
      listingId: LISTING_IDS.dal,
      reviewerId: buyer.id,
      rating: 5,
      comment:
        "Anita's dal is absolutely restaurant quality. Perfect spice level and so creamy!",
      tags: ["Tasty", "Fresh", "Value for money"],
      wouldOrderAgain: true,
      createdAt: pastOrderDate,
    },
  });

  console.log("Seed complete:");
  console.log(`  Societies: Prestige Notting Hill, Brigade Gateway, Sobha Dream Acres`);
  console.log(`  Seller: ${seller.name} (${SELLER_PHONE}) — Flat 3062 (Prestige)`);
  console.log(`  Buyer:  ${buyer.name} (${BUYER_PHONE}) — Flat 3062 (Prestige)`);
  console.log(`  Listings: ${listings.length} active items`);
  console.log(`  Past order: ${completedOrder.orderNumber} (completed + review)`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
