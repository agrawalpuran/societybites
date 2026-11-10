require("dotenv").config();
const prisma = require("../lib/prisma");
const { readConfig, graphMessagesUrl, templatePayload, orderTemplateParameters } = require("../lib/whatsappCloud");
const { toWhatsAppRecipient } = require("../lib/whatsappCloud");

async function main() {
  const orderNumber = process.argv[2] || "SE-987471";
  const order = await prisma.order.findUnique({
    where: { orderNumber },
    include: {
      buyer: true,
      items: { include: { listing: { include: { seller: true } } } },
    },
  });
  if (!order) {
    console.error("Order not found");
    process.exit(1);
  }

  const config = readConfig();
  const sellerPhone = order.items[0]?.listing?.seller?.phone;
  const to = toWhatsAppRecipient(sellerPhone);
  const parameters = orderTemplateParameters(order);

  console.log("Config:", {
    phoneNumberId: config.phoneNumberId,
    templateName: config.templateName,
    templateLanguage: config.templateLanguage,
  });
  console.log("To:", to, "from seller phone", sellerPhone);
  console.log("Body parameters count:", parameters?.length);
  console.log("Parameters:", parameters);

  const payload = templatePayload(to, {
    templateName: config.templateName,
    language: config.templateLanguage,
    parameters,
  });

  const url = graphMessagesUrl(config);
  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  const body = await response.json();
  console.log("HTTP", response.status);
  console.log(JSON.stringify(body, null, 2));

  // Phone number metadata
  const metaUrl = `https://graph.facebook.com/${config.apiVersion}/${config.phoneNumberId}?fields=display_phone_number,verified_name,quality_rating,account_mode`;
  const metaRes = await fetch(metaUrl, {
    headers: { Authorization: `Bearer ${config.token}` },
  });
  const meta = await metaRes.json();
  console.log("\nSender number metadata:");
  console.log(JSON.stringify(meta, null, 2));
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
