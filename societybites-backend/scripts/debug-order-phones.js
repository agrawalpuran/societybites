require("dotenv").config();
const prisma = require("../lib/prisma");
const { toWhatsAppRecipient, buyerPhoneFromOrder, sellerPhoneFromOrder } = require("../lib/whatsappCloud");

async function main() {
  const orderNumber = process.argv[2] || "SE-042476";
  const order = await prisma.order.findUnique({
    where: { orderNumber },
    include: {
      buyer: true,
      items: { include: { listing: { include: { seller: true } } } },
    },
  });
  if (!order) {
    console.log("Order not found");
    return;
  }
  const buyerRaw = buyerPhoneFromOrder(order);
  const sellerRaw = sellerPhoneFromOrder(order);
  console.log({
    orderNumber: order.orderNumber,
    status: order.status,
    buyerName: order.buyer?.name,
    buyerPhoneRaw: buyerRaw,
    buyerPhoneWhatsApp: toWhatsAppRecipient(buyerRaw),
    sellerPhoneRaw: sellerRaw,
    sellerPhoneWhatsApp: toWhatsAppRecipient(sellerRaw),
    buyerOnUpdatedShape: buyerPhoneFromOrder({ buyer: order.buyer }),
  });
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
