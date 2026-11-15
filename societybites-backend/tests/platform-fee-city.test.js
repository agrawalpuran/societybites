const { normalizeOverrides } = require("../lib/platformFee");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function main() {
  assert(
    JSON.stringify(normalizeOverrides({ bengaluru: 5, pune: 0 })) ===
      JSON.stringify({ bengaluru: 5, pune: 0 }),
    "normalize city overrides"
  );
  assert(
    Object.keys(normalizeOverrides({ bad: -1 })).length === 0,
    "drop invalid override"
  );
  console.log("platform-fee-city.test.js OK");
}

main();