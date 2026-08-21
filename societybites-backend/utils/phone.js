/**
 * Canonical SocietyBites phone: +91XXXXXXXXXX (E.164 India).
 * Accepts 9876543210, 919876543210, +919876543210.
 */
function normalizeIndianPhone(raw) {
  if (raw == null) return null;
  const digits = String(raw).replace(/\D/g, "");
  if (!digits) return null;

  let ten = digits;
  if (digits.length === 12 && digits.startsWith("91")) {
    ten = digits.slice(2);
  } else if (digits.length === 11 && digits.startsWith("0")) {
    ten = digits.slice(1);
  } else if (digits.length > 10) {
    ten = digits.slice(-10);
  }

  if (ten.length !== 10) return null;
  if (!/^[6-9]/.test(ten)) return null;

  return `+91${ten}`;
}

/** 2Factor typically wants 91XXXXXXXXXX (no plus). */
function toTwoFactorPhone(canonical) {
  if (!canonical || !canonical.startsWith("+91") || canonical.length !== 13) {
    return null;
  }
  return canonical.slice(1);
}

module.exports = { normalizeIndianPhone, toTwoFactorPhone };
