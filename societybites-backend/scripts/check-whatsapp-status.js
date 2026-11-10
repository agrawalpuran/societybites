require("dotenv").config();
const prisma = require("../lib/prisma");
const { isWhatsAppOrderNotificationsEnabled } = require("../lib/whatsappSetting");
const { readConfig, isConfigured } = require("../lib/whatsappCloud");

async function graphGet(cfg, path, searchParams = "") {
  const suffix = searchParams ? (searchParams.startsWith("?") ? searchParams : `?${searchParams}`) : "";
  const url = `https://graph.facebook.com/${cfg.apiVersion}/${path}${suffix}`;
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${cfg.token}` },
  });
  const body = await response.json();
  return { response, body };
}

async function main() {
  const adminOn = await isWhatsAppOrderNotificationsEnabled();
  const cfg = readConfig();
  const phoneNumberId = String(process.env.WHATSAPP_PHONE_NUMBER_ID || cfg.phoneNumberId || "").trim();
  const wabaId = String(process.env.WHATSAPP_BUSINESS_ACCOUNT_ID || "").trim();

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

  const phoneFields = [
    "id",
    "display_phone_number",
    "verified_name",
    "account_mode",
    "quality_rating",
  ].join(",");
  const phoneCheck = await graphGet(cfg, phoneNumberId, `fields=${phoneFields}`);
  if (!phoneCheck.response.ok) {
    console.log("--- Meta phone number check failed (token / phone ID) ---");
    console.log(phoneCheck.body && phoneCheck.body.error ? phoneCheck.body.error : phoneCheck.body);
    return;
  }

  console.log("--- Meta phone number (token OK for send API) ---");
  console.log(phoneCheck.body);

  if (!wabaId) {
    console.log(
      "--- Template list skipped ---",
    );
    console.log(
      "message_templates live on the WhatsApp Business Account ID, not the phone number ID.",
    );
    console.log(
      "Optional: set WHATSAPP_BUSINESS_ACCOUNT_ID in .env (WhatsApp Manager → your account URL or Business assets → WhatsApp accounts), then re-run.",
    );
    return;
  }

  const templateCheck = await graphGet(cfg, wabaId, "message_templates?limit=50");
  if (!templateCheck.response.ok) {
    console.log("--- Meta template list failed ---");
    console.log(templateCheck.body && templateCheck.body.error ? templateCheck.body.error : templateCheck.body);
    return;
  }

  const names = (templateCheck.body.data || []).map((t) => ({
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
