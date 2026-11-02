const prisma = require("./prisma");

const WHATSAPP_ORDER_NOTIFICATIONS_KEY = "whatsapp_order_notifications";

async function isWhatsAppOrderNotificationsEnabled() {
  const row = await prisma.appSetting.findUnique({
    where: { key: WHATSAPP_ORDER_NOTIFICATIONS_KEY },
  });
  if (!row) return false;
  const normalized = String(row.value || "").trim().toLowerCase();
  return normalized === "on" || normalized === "true" || normalized === "1";
}

async function setWhatsAppOrderNotifications(enabled) {
  const value = enabled ? "on" : "off";
  await prisma.appSetting.upsert({
    where: { key: WHATSAPP_ORDER_NOTIFICATIONS_KEY },
    update: { value },
    create: { key: WHATSAPP_ORDER_NOTIFICATIONS_KEY, value },
  });
  return enabled;
}

async function withWhatsAppOrderNotifications(enabled, fn) {
  const previous = await isWhatsAppOrderNotificationsEnabled();
  await setWhatsAppOrderNotifications(enabled);
  try {
    return await fn();
  } finally {
    await setWhatsAppOrderNotifications(previous);
  }
}

module.exports = {
  WHATSAPP_ORDER_NOTIFICATIONS_KEY,
  isWhatsAppOrderNotificationsEnabled,
  setWhatsAppOrderNotifications,
  withWhatsAppOrderNotifications,
};
