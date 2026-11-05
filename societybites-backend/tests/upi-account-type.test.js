const assert = require("assert");
const {
  DEFAULT_UPI_ACCOUNT_TYPE,
  normalizeUpiAccountType,
  isMerchantUpiAccountType,
  UPI_ACCOUNT_TYPES,
} = require("../lib/upiAccountType");

assert.strictEqual(DEFAULT_UPI_ACCOUNT_TYPE, "PERSONAL");
assert.strictEqual(normalizeUpiAccountType(undefined), "PERSONAL");
assert.strictEqual(normalizeUpiAccountType("personal"), "PERSONAL");
assert.strictEqual(normalizeUpiAccountType("MERCHANT"), "MERCHANT");
assert.strictEqual(normalizeUpiAccountType("business"), "MERCHANT");
assert.strictEqual(isMerchantUpiAccountType("MERCHANT"), true);
assert.strictEqual(isMerchantUpiAccountType("PERSONAL"), false);
assert.strictEqual(UPI_ACCOUNT_TYPES.PERSONAL, "PERSONAL");

let threw = false;
try {
  normalizeUpiAccountType("CARD");
} catch (err) {
  threw = true;
  assert.strictEqual(err.statusCode, 400);
}
assert.ok(threw, "invalid upiAccountType should throw");

console.log("upi-account-type.test.js passed");
