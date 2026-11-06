/**
 * Accounts created by backend integration tests / local OTP fixtures.
 * Used by Growth IST (hide from metrics) and cleanup-test-data.js.
 *
 * Seed pilot phones are never treated as automated test accounts.
 */

const PROTECTED_PHONES = new Set(["+919845154070", "+919901844776"]);

const PROTECTED_SOCIETY_IDS = new Set([
  "prestige-notting-hill",
  "brigade-gateway",
  "sobha-dream-acres",
]);

const TEST_SOCIETY_NAME =
  /^(Guest BLR |Guest Pune |P4B (Buyer|NearIn|NearOut|ExtOut|NoCoord|Pune) |PO (Buyer|Near|Mid|Far) |P5 (Buyer|Near|Far|NoCoord|Pune) |Catalog (buyer|nearby) )/;

/** Exact phones used across suites (also covered by prefixes below). */
const FIXED_TEST_PHONES = [
  "+919800000091",
  "+919800000093",
  "+919800000094",
  "+919800000095",
  "+919800000181",
  "+919800000182",
  "+919800000201",
  "+919800000202",
  "+919800000301",
  "+919800000302",
  "+919800000303",
  "+919800000304",
  "+919800000401",
  "+919800000402",
  "+919800000403",
  "+919800000411",
  "+919800000412",
  "+919800000501",
  "+919800000502",
  "+919800000503",
  "+919800000521",
  "+919800000522",
  "+919111000001",
  "+919111000002",
  "+919111000003",
  "+919111000018",
  "+919111000019",
  "+919111000028",
  "+919111000029",
  "+919111000039",
  "+919111000041",
  "+919111000042",
  "+919111000070",
  "+919111000071",
];

const FIXED_TEST_PHONE_SET = new Set(FIXED_TEST_PHONES);

/**
 * Synthetic prefixes reserved for automated tests:
 * - +919111000… ephemeral other-buyer/seller fixtures
 * - +919800000… feature-suite fixtures (many trailing zeros)
 */
const SYNTHETIC_TEST_PHONE_PREFIXES = Object.freeze([
  "+919111000",
  "+919800000",
]);

const AUTOMATED_TEST_USER_NAMES = new Set([
  "Guest Nearby Kitchen",
  "Guest Extended Kitchen",
  "Guest My Society Kitchen",
  "Guest Empty Kitchen",
  "Guest Preorder Kitchen",
  "Guest Pune Kitchen",
  "Guest Buyer",
  "Issue Buyer",
  "Issue Seller",
  "Issue Admin",
  "Reach Test Admin",
  "FSSAI Seller",
  "FSSAI Buyer",
  "FSSAI Admin",
  "Terms Buyer",
  "Delete Me",
  "Other Bulk Seller",
  "Bulk Buyer Only",
  "History Buyer",
  "History Seller",
  "Staff Owner Viewer",
  "Staff Stranger",
  "Messages Other Seller",
  "Messages Other Buyer",
  "Lifecycle Other Seller",
  "Lifecycle Other Buyer",
  "Cancel Other Buyer",
  "Order Reconciliation Other Buyer",
  "Coupon Buyer",
  "Coupon Other",
  "Coupon Admin",
  "Festival Admin",
  "Festival Buyer",
]);

function normalizePhone(raw) {
  const text = String(raw || "").trim();
  return text || "";
}

function isProtectedPhone(raw) {
  return PROTECTED_PHONES.has(normalizePhone(raw));
}

function matchesSyntheticTestPhonePrefix(phone) {
  return SYNTHETIC_TEST_PHONE_PREFIXES.some((prefix) => phone.startsWith(prefix));
}

function isAutomatedTestAccount(user) {
  if (!user) return false;
  const phone = normalizePhone(user.phone);
  if (phone && isProtectedPhone(phone)) return false;
  if (phone && FIXED_TEST_PHONE_SET.has(phone)) return true;
  if (phone && matchesSyntheticTestPhonePrefix(phone)) return true;
  const name = String(user.name || "").trim();
  if (name && AUTOMATED_TEST_USER_NAMES.has(name)) return true;
  return false;
}

/**
 * Prisma `where` fragment: AND with user queries so Growth excludes fixtures.
 * Seed phones are not listed here; prefixes / names already skip them.
 */
function automatedTestAccountExcludeWhere() {
  return {
    NOT: {
      OR: [
        { phone: { in: FIXED_TEST_PHONES } },
        ...SYNTHETIC_TEST_PHONE_PREFIXES.map((prefix) => ({
          phone: { startsWith: prefix },
        })),
        { name: { in: [...AUTOMATED_TEST_USER_NAMES] } },
      ],
    },
  };
}

module.exports = {
  PROTECTED_PHONES,
  PROTECTED_SOCIETY_IDS,
  TEST_SOCIETY_NAME,
  FIXED_TEST_PHONES,
  SYNTHETIC_TEST_PHONE_PREFIXES,
  AUTOMATED_TEST_USER_NAMES,
  isProtectedPhone,
  isAutomatedTestAccount,
  automatedTestAccountExcludeWhere,
};
