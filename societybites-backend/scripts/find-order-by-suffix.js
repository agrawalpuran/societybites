require("dotenv").config();
const prisma = require("../lib/prisma");

async function main() {
  const suffix = process.argv[2] || "592";
  const orders = await prisma.order.findMany({
    where: { orderNumber: { endsWith: suffix } },
    orderBy: { createdAt: "desc" },
    take: 3,
    select: {
      id: true,
      orderNumber: true,
      createdAt: true,
      status: true,
      buyer: { select: { phone: true, name: true } },
      items: {
        take: 1,
        include: { listing: { include: { seller: { select: { phone: true, name: true } } } } } },
      },
    },
  });
  console.log(JSON.stringify(orders, null, 2));
}

main().finally(() => prisma.$disconnect());
