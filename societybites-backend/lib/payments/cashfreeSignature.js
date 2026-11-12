const crypto = require("crypto");

function signCashfreeBody(rawBody, timestamp, secret) {
  return crypto
    .createHmac("sha256", secret)
    .update(`${timestamp}${rawBody}`)
    .digest("base64");
}

function verifyCashfreeSignature({ rawBody, timestamp, signature, secret }) {
  if (!rawBody || !timestamp || !signature || !secret) return false;
  const expected = signCashfreeBody(rawBody, timestamp, secret);
  const left = Buffer.from(expected);
  const right = Buffer.from(String(signature));
  if (left.length !== right.length) return false;
  return crypto.timingSafeEqual(left, right);
}

module.exports = { signCashfreeBody, verifyCashfreeSignature };
