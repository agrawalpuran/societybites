require("dotenv").config();
const prisma = require("../lib/prisma");
const { isWhatsAppOrderNotificationsEnabled } = require("../lib/whatsappSetting");
const {
  readConfig,
  isConfigured,
  toWhatsAppRecipient,
  sellerPhoneFromOrder,
  orderTemplateParameters,
} = require("../lib/whatsappCloud");

async function diagnoseOrder(order) {
  const adminOn = await isWhatsAppOrderNotificationsEnabled();
  const cfg = readConfig();
  const sellerRaw = sellerPhoneFromOrder(order);
  const sellerWa = toWhatsAppRecipient(sellerRaw);
  const reasons = [];
  if (!adminOn) reasons.push("admin_toggle_off");
  if (cfg.emergencyOff) reasons.push("WHATSAPP_ENABLED=false");
  if (!isConfigured(cfg)) reasons.push("missing_token_or_phone_number_id");
  if (!sellerWa) reasons.push(`seller_phone_invalid:${sellerRaw || "null"}`);

  const params = orderTemplateParameters(order);
  if (!params) reasons.push("invalid_order_amount");

  return {
    orderNumber: order.orderNumber,
    createdAt: order.createdAt,
    status: order.status,
    buyerPhone: order.buyer?.phone,
    buyerName: order.buyer?.name,
    sellerName: order.items?.[0]?.listing?.seller?.name,
    sellerPhone: sellerRaw,
    sellerWhatsAppTo: sellerWa,
    adminWhatsappOn: adminOn,
    template: cfg.templateName,
    wouldSkip: reasons.length ? reasons : null,
    canSendWhatsapp: reasons.length === 0,
  };
}

async function main() {
  const limit = Number(process.argv[2]) || 8;
  const orders = await prisma.order.findMany({
    orderBy: { createdAt: "desc" },
    take: limit,
    include: {
      buyer: { select: { name: true, phone: true } },
      items: {
        include: {
          listing: {
            include: { seller: { select: { name: true, phone: true } } },
          },
        },
      },
    },
  });

  console.log("--- Environment ---");
  const cfg = readConfig();
  console.log({
    template: cfg.templateName,
    apiConfigured: isConfigured(cfg),
    emergencyOff: cfg.emergencyOff,
    adminOn: await isWhatsAppOrderNotificationsEnabled(),
  });

  console.log("\n--- Recent orders ---");
  for (const order of orders) {
    const row = await diagnoseOrder(order);
    console.log(JSON.stringify(row, null, 2));
  }
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
