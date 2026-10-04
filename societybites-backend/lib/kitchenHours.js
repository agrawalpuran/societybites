const KITCHEN_CLOSED_MESSAGE = "Kitchen closed";
const IST_OFFSET_MS = (5 * 60 + 30) * 60 * 1000;

function httpError(statusCode, message, code) {
  const err = new Error(message);
  err.statusCode = statusCode;
  if (code) err.code = code;
  return err;
}

function isSellerRole(role) {
  return role === "seller" || role === "super_admin";
}

function normalizeClock(value, field) {
  if (value === null || value === undefined || value === "") return null;
  const match = /^(\d{1,2}):(\d{2})$/.exec(String(value).trim());
  if (!match) {
    throw httpError(400, `${field} must be HH:mm`);
  }
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (hour > 23 || minute > 59) {
    throw httpError(400, `${field} must be HH:mm`);
  }
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

function clockToMinutes(value) {
  if (value == null || value === "") return null;
  const match = /^(\d{1,2}):(\d{2})$/.exec(String(value).trim());
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

function istMinutes(date) {
  const shifted = new Date(date.getTime() + IST_OFFSET_MS);
  return shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
}

function assertKitchenHoursUpdate({ opensAt, closesAt, role }) {
  if (!isSellerRole(role)) {
    throw httpError(400, "Enable selling before setting kitchen hours");
  }
  const opens = normalizeClock(opensAt, "Open time");
  const closes = normalizeClock(closesAt, "Close time");
  if ((opens == null) !== (closes == null)) {
    throw httpError(400, "Set both an open time and a close time");
  }
  if (opens != null && opens === closes) {
    throw httpError(400, "Close time must be different from open time");
  }
  return { kitchenOpensAt: opens, kitchenClosesAt: closes };
}

/**
 * Unset hours stay open. A window that passes midnight (close earlier than
 * open) stays open until the close time.
 */
function isKitchenOpen(seller, now = new Date()) {
  const open = clockToMinutes(seller && seller.kitchenOpensAt);
  const close = clockToMinutes(seller && seller.kitchenClosesAt);
  if (open == null || close == null) return true;
  if (open === close) return false;
  const current = istMinutes(now);
  if (open < close) return current >= open && current < close;
  return current >= open || current < close;
}

function assertKitchenOpen(seller, now = new Date()) {
  if (isKitchenOpen(seller, now)) return;
  throw httpError(400, KITCHEN_CLOSED_MESSAGE, "KITCHEN_CLOSED");
}

async function assertSellerKitchenOpen(prisma, sellerId, now = new Date()) {
  const seller = await prisma.user.findUnique({
    where: { id: sellerId },
    select: { kitchenOpensAt: true, kitchenClosesAt: true },
  });
  assertKitchenOpen(seller, now);
}

module.exports = {
  KITCHEN_CLOSED_MESSAGE,
  assertKitchenHoursUpdate,
  isKitchenOpen,
  assertKitchenOpen,
  assertSellerKitchenOpen,
  istMinutes,
};
