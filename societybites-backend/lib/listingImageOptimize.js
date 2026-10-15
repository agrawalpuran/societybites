const sharp = require("sharp");

const MAX_EDGE = 1200;
const JPEG_QUALITY = 82;

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

/**
 * Resize listing food photos for Storage/CDN. Preserves aspect ratio and EXIF
 * orientation. Never enlarges. Output is JPEG unless the source is tiny PNG
 * with alpha (kept as PNG when resize is a no-op and alpha is required).
 */
async function optimizeListingPhoto(buffer) {
  if (!buffer || !buffer.length) {
    throw httpError(400, "Invalid image data");
  }

  try {
    let pipeline = sharp(buffer, { failOn: "error" }).rotate();
    const metadata = await pipeline.metadata();
    if (!metadata.width || !metadata.height) {
      throw httpError(400, "Unsupported photo type. Use JPG, PNG, or WebP.");
    }

    const needsResize =
      metadata.width > MAX_EDGE || metadata.height > MAX_EDGE;
    if (needsResize) {
      pipeline = pipeline.resize({
        width: MAX_EDGE,
        height: MAX_EDGE,
        fit: "inside",
        withoutEnlargement: true,
      });
    }

    const out = await pipeline
      .jpeg({ quality: JPEG_QUALITY, mozjpeg: true })
      .toBuffer();
    return { buffer: out, mimeType: "image/jpeg" };
  } catch (err) {
    if (err.statusCode) throw err;
    throw httpError(400, "Unsupported photo type. Use JPG, PNG, or WebP.");
  }
}

module.exports = {
  MAX_EDGE,
  JPEG_QUALITY,
  optimizeListingPhoto,
};
