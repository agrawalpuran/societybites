const https = require("https");

const logger = require("./logger");

const BASE = "https://2factor.in/API/V1";

let insecureTlsAgent;
function twoFactorHttpsAgent() {
  const insecure =
    String(process.env.TWOFACTOR_TLS_INSECURE || "").trim().toLowerCase() ===
    "true";
  if (!insecure) return undefined;
  if (!insecureTlsAgent) {
    logger.warn(
      "twofactor",
      "TWOFACTOR_TLS_INSECURE=true — TLS verification disabled for 2Factor only (local dev)"
    );
    insecureTlsAgent = new https.Agent({ rejectUnauthorized: false });
  }
  return insecureTlsAgent;
}

function apiKey() {
  return process.env.TWOFACTOR_API_KEY || "";
}

function isConfigured() {
  return Boolean(apiKey());
}

function smsReachabilityMessage(cause) {
  const code = cause && cause.code ? String(cause.code) : "";
  if (code === "SELF_SIGNED_CERT_IN_CHAIN" || code === "UNABLE_TO_VERIFY_LEAF_SIGNATURE") {
    return (
      "Could not reach the SMS provider (TLS blocked by a corporate proxy). " +
      "For local dev set NODE_EXTRA_CA_CERTS to your company root CA, or " +
      "TWOFACTOR_TLS_INSECURE=true in .env (dev only)."
    );
  }
  return "Could not reach the SMS provider. Check network access to 2factor.in.";
}

function getJson(url) {
  return new Promise((resolve, reject) => {
    const agent = twoFactorHttpsAgent();
    const req = https.get(url, { agent }, (res) => {
      let body = "";
      res.on("data", (chunk) => {
        body += chunk;
      });
      res.on("end", () => {
        let data;
        try {
          data = JSON.parse(body);
        } catch {
          data = { Status: "Error", Details: "Invalid 2Factor response" };
        }
        resolve({
          ok: res.statusCode >= 200 && res.statusCode < 300,
          data,
        });
      });
    });
    req.on("error", (err) => {
      logger.warn("twofactor", "HTTP request failed", {
        message: err.message,
        code: err.code,
      });
      const smsErr = new Error(smsReachabilityMessage(err));
      smsErr.statusCode = 502;
      reject(smsErr);
    });
  });
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
