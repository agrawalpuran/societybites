/**
 * Local/dev OTP bypass. Disabled unless TEST_OTP_ENABLED=true.
 * Numbers and OTP stay in env only — never send them in API responses.
 */

function isEnabled() {
  return String(process.env.TEST_OTP_ENABLED || "").trim().toLowerCase() === "true";
}

function tenDigits(raw) {
  const digits = String(raw || "").replace(/\D/g, "");
  if (!digits) return null;
  if (digits.length === 12 && digits.startsWith("91")) return digits.slice(2);
  if (digits.length === 11 && digits.startsWith("0")) return digits.slice(1);
  if (digits.length === 10) return digits;
  if (digits.length > 10) return digits.slice(-10);
  return null;
}

function testNumberSet() {
  return new Set(
    String(process.env.TEST_PHONE_NUMBERS || "")
      .split(",")
      .map((part) => tenDigits(part.trim()))
      .filter(Boolean)
  );
}

function isTestPhone(raw) {
  if (!isEnabled()) return false;
  const ten = tenDigits(raw);
  if (!ten) return false;
  return testNumberSet().has(ten);
}

/** Canonical +91XXXXXXXXXX for a configured test number, else null. */
function canonicalTestPhone(raw) {
  if (!isTestPhone(raw)) return null;
  return `+91${tenDigits(raw)}`;
}

function otpMatches(otp) {
  if (!isEnabled()) return false;
  const expected = String(process.env.TEST_OTP || "").trim();
  if (!expected) return false;
  return String(otp || "").trim() === expected;
}

module.exports = {
  isEnabled,
  isTestPhone,
  canonicalTestPhone,
  otpMatches,
};
