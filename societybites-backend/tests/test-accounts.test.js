const {
  isAutomatedTestAccount,
  automatedTestAccountExcludeWhere,
  FIXED_TEST_PHONES,
} = require("../lib/testAccounts");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

assert(
  isAutomatedTestAccount({
    name: "History Buyer",
    phone: "+919111000071",
  }),
  "History Buyer is a test account"
);
assert(
  isAutomatedTestAccount({
    name: "History Seller",
    phone: "+919111000070",
  }),
  "History Seller is a test account"
);
assert(
  isAutomatedTestAccount({ name: "Real Neighbor", phone: "+919111000099" }),
  "synthetic +919111000 prefix is treated as test"
);
assert(
  isAutomatedTestAccount({ name: "Suite Fixture", phone: "+919800000999" }),
  "synthetic +919800000 prefix is treated as test"
);
assert(
  isAutomatedTestAccount({ name: "Issue Buyer", phone: "+918812345678" }),
  "known test display name is treated as test"
);

assert(
  !isAutomatedTestAccount({
    name: "Puran",
    phone: "+919845154070",
  }),
  "seed buyer is never a test account"
);
assert(
  !isAutomatedTestAccount({
    name: "Anita",
    phone: "+919901844776",
  }),
  "seed seller is never a test account"
);
assert(
  !isAutomatedTestAccount({
    name: "Neighbor Meera",
    phone: "+919876543210",
  }),
  "ordinary pilot phone is not a test account"
);

assert(FIXED_TEST_PHONES.includes("+919111000071"), "history buyer phone listed");
assert(FIXED_TEST_PHONES.includes("+919111000070"), "history seller phone listed");

const exclude = automatedTestAccountExcludeWhere();
assert(exclude.NOT && Array.isArray(exclude.NOT.OR), "prisma exclude shape");
assert(
  exclude.NOT.OR.some(
    (clause) =>
      clause.phone &&
      Array.isArray(clause.phone.in) &&
      clause.phone.in.includes("+919111000071")
  ),
  "exclude lists history buyer phone"
);
assert(
  exclude.NOT.OR.some(
    (clause) =>
      clause.name &&
      Array.isArray(clause.name.in) &&
      clause.name.in.includes("History Buyer")
  ),
  "exclude lists History Buyer name"
);

console.log("test-accounts.test.js: all assertions passed");
