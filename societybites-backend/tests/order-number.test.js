const { generateOrderNumber } = require("../utils/orderNumber");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const sample = generateOrderNumber();
assert(/^SE-\d{6}$/.test(sample), `expected SE- prefix, got ${sample}`);
console.log("order number ok");
