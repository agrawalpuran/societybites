const jwt = require("jsonwebtoken");

const JWT_SECRET = process.env.JWT_SECRET || "societybites-dev-secret-change-in-production";
const JWT_EXPIRY = process.env.JWT_EXPIRY || "7d";
const ACCESS_TOKEN_EXPIRY = process.env.ACCESS_TOKEN_EXPIRY || "15m";

function tokenPayload(user) {
  return {
    userId: user.id,
    phone: user.phone,
    role: user.role,
    societyId: user.societyId,
  };
}

function signToken(user) {
  return jwt.sign(tokenPayload(user), JWT_SECRET, { expiresIn: JWT_EXPIRY });
}

/** Short-lived access JWT for 2Factor sessions. Same payload as signToken. */
function signAccessToken(user) {
  return jwt.sign(tokenPayload(user), JWT_SECRET, {
    expiresIn: ACCESS_TOKEN_EXPIRY,
  });
}

function verifyToken(token) {
  return jwt.verify(token, JWT_SECRET);
}

module.exports = {
  signToken,
  signAccessToken,
  verifyToken,
  JWT_SECRET,
  ACCESS_TOKEN_EXPIRY,
};
