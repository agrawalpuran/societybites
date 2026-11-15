const {
  groupSocietyIdsByCityKey,
  parseAdminCityKeyQuery,
} = require("../lib/adminCityDashboard");
const { filterCouponsForCityScope } = require("../lib/coupons");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function main() {
  assert(parseAdminCityKeyQuery({}) === null, "missing cityKey is all");
  assert(parseAdminCityKeyQuery({ cityKey: "" }) === null, "empty is all");
  assert(parseAdminCityKeyQuery({ cityKey: "all" }) === null, "all token");
  assert(parseAdminCityKeyQuery({ cityKey: " Pune " }) === "pune", "trim lower");

  const grouped = groupSocietyIdsByCityKey([
    { id: "s1", city: "Bengaluru" },
    { id: "s2", city: "Bangalore" },
    { id: "s3", city: "Pune" },
  ]);
  assert(grouped.get("bengaluru").length === 2, "Bangalore collapses to Bengaluru");
  assert(grouped.get("pune").length === 1, "Pune row");

  const scoped = filterCouponsForCityScope(
    [
      { code: "ALL", eligibleSocietyIds: [] },
      { code: "PNH", eligibleSocietyIds: ["s3"] },
      { code: "BLR", eligibleSocietyIds: ["s1"] },
    ],
    ["s3"]
  );
  assert(scoped.length === 2, "city filter keeps global + matching society coupons");

  console.log("admin-city-dashboard.test.js OK");
}

main();