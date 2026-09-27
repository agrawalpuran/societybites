const { MAX_BYTES } = require("./objectStorage");

const ALLOWED_MIME_TYPES = new Set([
  "image/jpeg",
  "image/jpg",
  "image/png",
  "image/webp",
]);

const TOO_LARGE_MESSAGE = "Photo is too large. Please choose another photo.";
const UNSUPPORTED_MESSAGE = "Unsupported photo type. Use JPG, PNG, or WebP.";

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function looksLikeImage(buffer) {
  if (!buffer || buffer.length < 12) return false;
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return true;
  if (
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47
  ) {
    return true;
  }
  const riff = buffer.slice(0, 4).toString("ascii");
  const webp = buffer.slice(8, 12).toString("ascii");
  return riff === "RIFF" && webp === "WEBP";
}

function normalizeMimeType(raw) {
  const mime = String(raw || "image/jpeg").trim().toLowerCase();
  if (!ALLOWED_MIME_TYPES.has(mime)) {
    throw httpError(400, UNSUPPORTED_MESSAGE);
  }
  return mime === "image/jpg" ? "image/jpeg" : mime;
}

function parseImageUpload(body) {
  if (!body || body.imageBase64 == null || body.imageBase64 === "") {
    throw httpError(400, "imageBase64 is required");
  }
  const mimeType = normalizeMimeType(body.mimeType);
  let buffer;
  try {
    buffer = Buffer.from(String(body.imageBase64), "base64");
  } catch (_) {
    throw httpError(400, "Invalid image data");
  }
  if (!buffer.length) {
    throw httpError(400, "Invalid image data");
  }
  if (buffer.length > MAX_BYTES) {
    throw httpError(400, TOO_LARGE_MESSAGE);
  }
  if (!looksLikeImage(buffer)) {
    throw httpError(400, UNSUPPORTED_MESSAGE);
  }
  return { buffer, mimeType };
}

function storagePrefixForPurpose(purpose) {
  return String(purpose || "").trim().toLowerCase() === "profile"
    ? "profiles"
    : "listings";
}

function normalizeStoredProfilePhotoUrl(value) {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string") {
    throw httpError(400, "profilePhotoUrl must be a string or null");
  }
  const trimmed = value.trim();
  if (!trimmed || trimmed === "null") return null;
  const lower = trimmed.toLowerCase();
  if (lower.startsWith("javascript:") || lower.startsWith("data:")) {
    throw httpError(400, "Invalid profile photo URL");
  }
  if (
    trimmed.startsWith("https://") ||
    trimmed.startsWith("http://") ||
    trimmed.startsWith("/uploads/")
  ) {
    if (trimmed.length > 2000) {
      throw httpError(400, "Invalid profile photo URL");
    }
    return trimmed;
  }
  throw httpError(400, "Invalid profile photo URL");
}

module.exports = {
  ALLOWED_MIME_TYPES,
  TOO_LARGE_MESSAGE,
  UNSUPPORTED_MESSAGE,
  looksLikeImage,
  parseImageUpload,
  storagePrefixForPurpose,
  normalizeStoredProfilePhotoUrl,
};
