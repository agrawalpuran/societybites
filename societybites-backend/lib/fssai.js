function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function isSellerRole(role) {
  return role === "seller" || role === "super_admin";
}

function digitsOnly(value) {
  return String(value || "").replace(/\D/g, "");
}

function serializeFssai(user) {
  const number = user && user.fssaiNumber ? String(user.fssaiNumber) : null;
  return {
    number,
    expiry: user && user.fssaiExpiry ? user.fssaiExpiry : null,
    registeredName:
      user && user.fssaiRegisteredName ? String(user.fssaiRegisteredName) : null,
  };
}

function parseFssaiNumber(value) {
  if (value == null) return undefined;
  const trimmed = String(value).trim();
  if (!trimmed) return null;
  const digits = digitsOnly(trimmed);
  if (!/^\d{14}$/.test(digits)) {
    throw httpError(400, "FSSAI licence number must be 14 digits");
  }
  return digits;
}

function parseFssaiExpiry(value) {
  if (value == null) return undefined;
  if (value === "") return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw httpError(400, "FSSAI expiry must be a valid date");
  }
  return parsed;
}

function parseFssaiRegisteredName(value) {
  if (value == null) return undefined;
  const trimmed = String(value).trim();
  if (!trimmed) return null;
  if (trimmed.length > 120) {
    throw httpError(400, "Registered name must be 120 characters or fewer");
  }
  return trimmed;
}

function assertSellerFssaiUpdate({ role, number, expiry, registeredName } = {}) {
  if (!isSellerRole(role)) {
    throw httpError(400, "Only sellers can update FSSAI details");
  }
  const fssaiNumber = parseFssaiNumber(number);
  let fssaiExpiry = parseFssaiExpiry(expiry);
  let fssaiRegisteredName = parseFssaiRegisteredName(registeredName);
  if (fssaiNumber === null) {
    fssaiExpiry = null;
    fssaiRegisteredName = null;
  }
  const data = {};
  if (fssaiNumber !== undefined) data.fssaiNumber = fssaiNumber;
  if (fssaiExpiry !== undefined) data.fssaiExpiry = fssaiExpiry;
  if (fssaiRegisteredName !== undefined) data.fssaiRegisteredName = fssaiRegisteredName;
  return data;
}

module.exports = {
  serializeFssai,
  parseFssaiNumber,
  assertSellerFssaiUpdate,
};
