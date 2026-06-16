function generateOrderNumber() {
  const suffix = Date.now().toString().slice(-4);
  const random = Math.floor(Math.random() * 90 + 10);
  return `SB-${suffix}${random}`;
}

module.exports = { generateOrderNumber };
