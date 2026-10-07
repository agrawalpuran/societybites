require("dotenv").config();
const twoFactor = require("../lib/twoFactor");

const phone = process.argv[2] || "919876543210";

twoFactor
  .sendOtp(phone)
  .then((r) => {
    console.log("Success, sessionId length:", String(r.sessionId).length);
  })
  .catch((e) => {
    console.error("Failed:", e.statusCode || "no-status", e.message);
    if (e.cause) console.error("Cause:", e.cause);
    process.exitCode = 1;
  });
