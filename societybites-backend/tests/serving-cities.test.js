/**
 * Serving-city rules. No database: a missing list stays on the env city,
 * and only cities with a map center can be turned on.
 */
const {
  applyLaunchCityConfig,
  clearLaunchCityConfig,
  configForActiveKeys,
  getLaunchCityConfig,
  listKnownCities,
  normalizeActiveCityKeys,
  placeMatchesLaunchCity,
  servingCityPayload,
  suggestionMatchesLaunchCity,
} = require("../lib/launchCity");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const bengaluru = {
  name: "Mantri Residency",
  address: "Bannerghatta Road, Bengaluru, Karnataka, India",
};
const bangalore = {
  name: "Spring Valley",
  address: "Sarjapur Road, Bangalore, Karnataka, India",
};
const pune = {
  name: "Mantri Residency",
  address: "Baner, Pune, Maharashtra, India",
};
const hyderabad = {
  name: "My Home Bhooja",
  address: "Gachibowli, Hyderabad, Telangana, India",
};

function main() {
  clearLaunchCityConfig();

  const fallback = getLaunchCityConfig();
  assert(fallback.bias, "default Bengaluru search keeps a map circle");
  assert(
    suggestionMatchesLaunchCity(bengaluru),
    "default filter keeps Bengaluru"
  );
  assert(
    suggestionMatchesLaunchCity(bangalore),
    "default filter keeps Bangalore"
  );
  assert(!suggestionMatchesLaunchCity(pune), "default filter drops Pune");

  const one = configForActiveKeys(["bengaluru"]);
  assert(one && one.canonical === "bengaluru", "Bengaluru key resolves");
  assert(one.bias && Number.isFinite(one.bias.latitude), "one city keeps a circle");
  assert(suggestionMatchesLaunchCity(bangalore, one), "Bangalore matches Bengaluru");
  assert(!suggestionMatchesLaunchCity(pune, one), "Pune stays off while only Bengaluru is on");
  assert(
    placeMatchesLaunchCity({ city: "Bangalore", state: "Karnataka" }, one),
    "join still accepts Bangalore"
  );

  const both = configForActiveKeys(["pune", "bengaluru"]);
  assert(both.bias === null, "two cities do not send one map circle");
  assert(
    both.canonicals.join(",") === "bengaluru,pune",
    "active cities stay in catalog order"
  );
  assert(both.city === "Bengaluru and Pune", "label names both cities");
  assert(suggestionMatchesLaunchCity(bengaluru, both), "Bengaluru stays searchable");
  assert(suggestionMatchesLaunchCity(pune, both), "Pune becomes searchable");
  assert(!suggestionMatchesLaunchCity(hyderabad, both), "Hyderabad stays off");
  assert(
    servingCityPayload(both).servingCityLabel === "Bengaluru and Pune",
    "public label matches the active cities"
  );

  const puneOnly = configForActiveKeys(["pune"]);
  assert(puneOnly.bias && puneOnly.bias.latitude > 18, "Pune uses its own circle");
  assert(!suggestionMatchesLaunchCity(bengaluru, puneOnly), "Bengaluru is off when only Pune is on");

  assert(
    normalizeActiveCityKeys(["Bangalore"]).join(",") === "bengaluru",
    "Bangalore saves as Bengaluru"
  );
  assert(
    listKnownCities().some((city) => city.cityKey === "bengaluru"),
    "catalog includes Bengaluru"
  );

  let unknown = null;
  try {
    normalizeActiveCityKeys(["Jaipur"]);
  } catch (err) {
    unknown = err;
  }
  assert(unknown && unknown.code === "SERVING_CITY_UNKNOWN", "unknown city is rejected");

  let empty = null;
  try {
    normalizeActiveCityKeys([]);
  } catch (err) {
    empty = err;
  }
  assert(empty && empty.code === "SERVING_CITY_REQUIRED", "last city cannot be turned off");

  applyLaunchCityConfig(both);
  assert(getLaunchCityConfig().bias === null, "applied config is what search reads");
  clearLaunchCityConfig();
  assert(getLaunchCityConfig().bias, "clearing the list returns to the default circle");
  assert(!suggestionMatchesLaunchCity(pune), "cleared config drops Pune again");

  console.log("serving cities ok");
}

main();
