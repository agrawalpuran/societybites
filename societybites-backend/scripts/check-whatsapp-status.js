require("dotenv").config();
const prisma = require("../lib/prisma");
const { isWhatsAppOrderNotificationsEnabled } = require("../lib/whatsappSetting");
const { readConfig, isConfigured } = require("../lib/whatsappCloud");

async function main() {
  const adminOn = await isWhatsAppOrderNotificationsEnabled();
  const cfg = readConfig();
  console.log("--- Local env + DB ---");
  console.log({
    adminWhatsappToggle: adminOn,
    templateName: cfg.templateName,
    templateLanguage: cfg.templateLanguage,
    apiConfigured: isConfigured(cfg),
    emergencyOff: cfg.emergencyOff,
  });

  if (!isConfigured(cfg)) {
    console.log("STOP: Missing WHATSAPP_TOKEN or WHATSAPP_PHONE_NUMBER_ID");
    return;
  }

  const url = `https://graph.facebook.com/${cfg.apiVersion}/${process.env.WHATSAPP_PHONE_NUMBER_ID}/message_templates?limit=50`;
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${cfg.token}` },
  });
  const body = await response.json();
  if (!response.ok) {
    console.log("--- Meta template list failed ---");
    console.log(body && body.error ? body.error : body);
    return;
  }

  const names = (body.data || []).map((t) => ({
    name: t.name,
    status: t.status,
    language: t.language,
  }));
  const wanted = cfg.templateName;
  const match = names.filter((t) => t.name === wanted);
  console.log("--- Template", wanted, "---");
  if (match.length === 0) {
    console.log("NOT FOUND in WABA. Available:", names.map((t) => `${t.name} (${t.status})`).join(", "));
  } else {
    console.log(match);
  }
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
