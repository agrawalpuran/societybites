const {
  isAutomatedTestListingName,
  withoutAutomatedTestListings,
} = require("../lib/testListingNames");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

assert(isAutomatedTestListingName("Cancel 1791447461402"), "cancel test listing");
assert(isAutomatedTestListingName("Dbg1791447418913"), "debug listing");
assert(isAutomatedTestListingName("Lifecycle 1710000000000"), "lifecycle listing");
assert(!isAutomatedTestListingName("Home made fresh idli"), "real dish name");

const filtered = withoutAutomatedTestListings([
  { id: "1", name: "Cancel 1791447461402" },
  { id: "2", name: "Samosa" },
]);
assert(filtered.length === 1 && filtered[0].name === "Samosa", "filter keeps real listings");

console.log("test-listing-names.test.js: all assertions passed");
