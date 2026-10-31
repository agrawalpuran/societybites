/**
 * Delete orders by order number (e.g. SE-225368).
 *
 *   node scripts/delete-orders-by-number.js SE-225368
 *   node scripts/delete-orders-by-number.js SE-225368 SE-225369 --apply
 */
require("dotenv").config();
const prisma = require("../lib/prisma");

function parseArgs(argv) {
  const apply = argv.includes("--apply");
  const numbers = argv
    .filter((arg) => arg !== "--apply")
    .map((arg) => String(arg).trim().toUpperCase())
    .filter(Boolean);
  return { apply, numbers };
}

async function main() {
  const { apply, numbers } = parseArgs(process.argv.slice(2));
  if (numbers.length === 0) {
    console.error("Pass one or more order numbers, e.g. SE-225368");
    process.exitCode = 1;
    return;
  }

  const orders = await prisma.order.findMany({
    where: { orderNumber: { in: numbers } },
    select: {
      id: true,
      orderNumber: true,
      status: true,
      paymentStatus: true,
      total: true,
      createdAt: true,
      buyer: { select: { name: true, phone: true } },
      _count: { select: { items: true } },
    },
  });

  const found = new Set(orders.map((order) => order.orderNumber));
  for (const number of numbers) {
    if (!found.has(number)) console.log(`not found: ${number}`);
  }

  for (const order of orders) {
    console.log(
      `${order.orderNumber} | ${order.status}/${order.paymentStatus} | ₹${order.total} | items ${order._count.items} | ${order.buyer.name || "(no name)"} | ${order.createdAt.toISOString()}`
    );
  }
  console.log(`matched ${orders.length}`);

  if (!apply) {
    console.log("dry run only — add --apply to delete");
    return;
  }

  const orderIds = orders.map((order) => order.id);
  if (orderIds.length === 0) return;

  await prisma.message.deleteMany({ where: { orderId: { in: orderIds } } });
  await prisma.review.deleteMany({ where: { orderId: { in: orderIds } } });
  await prisma.couponRedemption.deleteMany({ where: { orderId: { in: orderIds } } });
  await prisma.orderIdempotency.deleteMany({ where: { orderId: { in: orderIds } } });
  await prisma.orderItem.deleteMany({ where: { orderId: { in: orderIds } } });
  await prisma.order.deleteMany({ where: { id: { in: orderIds } } });
  console.log(`deleted ${orderIds.length}`);
}

main()
  .catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
