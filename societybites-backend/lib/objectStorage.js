const { createClient } = require("@supabase/supabase-js");

const BUCKET = process.env.SUPABASE_STORAGE_BUCKET || "listing-images";
const MAX_BYTES = 5 * 1024 * 1024;

let client;
let bucketReady;

function storageConfig() {
  const url = (process.env.SUPABASE_URL || "").trim();
  const key = (
    process.env.SUPABASE_SERVICE_ROLE_KEY ||
    process.env.SUPABASE_KEY ||
    ""
  ).trim();
  return { url, key };
}

function isObjectStorageConfigured() {
  const { url, key } = storageConfig();
  return Boolean(url && key);
}

function getClient() {
  if (!isObjectStorageConfigured()) return null;
  if (client) return client;
  const { url, key } = storageConfig();
  client = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return client;
}

function extensionForMime(mimeType) {
  if (typeof mimeType === "string" && mimeType.includes("png")) return "png";
  if (typeof mimeType === "string" && mimeType.includes("webp")) return "webp";
  return "jpg";
}

function contentTypeForExt(ext) {
  if (ext === "png") return "image/png";
  if (ext === "webp") return "image/webp";
  return "image/jpeg";
}

async function ensureBucket() {
  const supabase = getClient();
  if (!supabase) {
    const err = new Error(
      "Image storage is not configured. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY."
    );
    err.statusCode = 503;
    throw err;
  }
  if (bucketReady) return supabase;

  const { data, error } = await supabase.storage.getBucket(BUCKET);
  if (error || !data) {
    const created = await supabase.storage.createBucket(BUCKET, {
      public: true,
      fileSizeLimit: MAX_BYTES,
      allowedMimeTypes: ["image/jpeg", "image/png", "image/webp", "image/jpg"],
    });
    if (created.error && !String(created.error.message || "").includes("already exists")) {
      const err = new Error("Could not prepare image storage");
      err.statusCode = 503;
      throw err;
    }
  } else if (data.public === false) {
    await supabase.storage.updateBucket(BUCKET, { public: true });
  }

  bucketReady = true;
  return supabase;
}

async function uploadPublicImage({ buffer, mimeType, userId, prefix = "listings" }) {
  if (!buffer || !buffer.length) {
    const err = new Error("Invalid image data");
    err.statusCode = 400;
    throw err;
  }
  if (buffer.length > MAX_BYTES) {
    const err = new Error("Image too large (max 5 MB)");
    err.statusCode = 400;
    throw err;
  }

  const supabase = await ensureBucket();
  const ext = extensionForMime(mimeType);
  const safeUser = String(userId || "anonymous").replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 12);
  const objectPath = `${prefix}/${safeUser || "user"}/${Date.now()}-${Math.random()
    .toString(36)
    .slice(2, 8)}.${ext}`;

  const { error } = await supabase.storage.from(BUCKET).upload(objectPath, buffer, {
    contentType: contentTypeForExt(ext),
    upsert: false,
  });
  if (error) {
    const err = new Error("Could not store the image. Please try again.");
    err.statusCode = 502;
    throw err;
  }

  const { data } = supabase.storage.from(BUCKET).getPublicUrl(objectPath);
  if (!data?.publicUrl) {
    const err = new Error("Could not create a public image URL");
    err.statusCode = 502;
    throw err;
  }
  return data.publicUrl;
}

async function uploadLocalFile({ filePath, mimeType, userId, prefix }) {
  const fs = require("fs");
  const buffer = fs.readFileSync(filePath);
  return uploadPublicImage({ buffer, mimeType, userId, prefix });
}

module.exports = {
  BUCKET,
  MAX_BYTES,
  isObjectStorageConfigured,
  uploadPublicImage,
  uploadLocalFile,
  extensionForMime,
};
