const logger = require("./logger");

const BASE = "https://2factor.in/API/V1";

function apiKey() {
  return process.env.TWOFACTOR_API_KEY || "";
}

function isConfigured() {
  return Boolean(apiKey());
}

async function getJson(url) {
  const res = await fetch(url);
  let data;
  try {
    data = await res.json();
  } catch {
    data = { Status: "Error", Details: "Invalid 2Factor response" };
  }
  return { ok: res.ok, data };
}

/**
 * AUTOGEN — 2Factor stores the OTP. Details is the session id (not the OTP).
 */
async function sendOtp(phone91) {
  const key = apiKey();
  if (!key) {
    const err = new Error("2Factor is not configured");
    err.statusCode = 503;
    throw err;
  }

  const template = process.env.TWOFACTOR_OTP_TEMPLATE;
  const path = template
    ? `${BASE}/${encodeURIComponent(key)}/SMS/${encodeURIComponent(phone91)}/AUTOGEN2/${encodeURIComponent(template)}`
    : `${BASE}/${encodeURIComponent(key)}/SMS/${encodeURIComponent(phone91)}/AUTOGEN`;

  const { data } = await getJson(path);
  if (data.Status !== "Success" || !data.Details) {
    logger.warn("twofactor", "send OTP failed", {
      details: data.Details || data.Status,
    });
    const err = new Error("Could not send OTP. Please try again later.");
    err.statusCode = 502;
    throw err;
  }
  return { sessionId: String(data.Details) };
}

async function verifyOtp(sessionId, otp) {
  const key = apiKey();
  if (!key) {
    const err = new Error("2Factor is not configured");
    err.statusCode = 503;
    throw err;
  }

  const path = `${BASE}/${encodeURIComponent(key)}/SMS/VERIFY/${encodeURIComponent(sessionId)}/${encodeURIComponent(otp)}`;
  const { data } = await getJson(path);
  const matched =
    data.Status === "Success" &&
    String(data.Details || "")
      .toLowerCase()
      .includes("match");
  return { matched, details: data.Details || data.Status };
}

module.exports = { isConfigured, sendOtp, verifyOtp };
