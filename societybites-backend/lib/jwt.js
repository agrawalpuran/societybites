const jwt = require("jsonwebtoken");

const JWT_SECRET = process.env.JWT_SECRET || "societybites-dev-secret-change-in-production";
const JWT_EXPIRY = process.env.JWT_EXPIRY || "7d";

function signToken(user) {
  return jwt.sign(
    {
      userId: user.id,
      phone: user.phone,
      role: user.role,
      societyId: user.societyId,
    },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRY }
  );
}

function verifyToken(token) {
  return jwt.verify(token, JWT_SECRET);
}

module.exports = { signToken, verifyToken, JWT_SECRET };
