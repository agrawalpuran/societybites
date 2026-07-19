function validatePhone(phone) {
  return /^\+91\d{10}$/.test(phone);
}

function validateUpiId(upi) {
  return /^[\w.\-]+@[\w]+$/.test(upi);
}

function validatePrice(price) {
  const p = parseFloat(price);
  return !isNaN(p) && p > 0 && p <= 50000;
}

function validateQuantity(qty) {
  const q = parseInt(qty, 10);
  return !isNaN(q) && q >= 1 && q <= 1000;
}

function validateRating(rating) {
  const r = parseInt(rating, 10);
  return !isNaN(r) && r >= 1 && r <= 5;
}

module.exports = { validatePhone, validateUpiId, validatePrice, validateQuantity, validateRating };
