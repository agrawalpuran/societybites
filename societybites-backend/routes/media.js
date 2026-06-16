const express = require("express");
const fs = require("fs");
const path = require("path");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");

const router = express.Router();
const UPLOADS_DIR = path.join(__dirname, "..", "uploads");
const MAX_BYTES = 5 * 1024 * 1024;

if (!fs.existsSync(UPLOADS_DIR)) {
  fs.mkdirSync(UPLOADS_DIR, { recursive: true });
}

router.post(
  "/upload",
  requireUser,
  asyncHandler(async (req, res) => {
    const { imageBase64, mimeType = "image/jpeg" } = req.body;

    if (!imageBase64) {
      return res.status(400).json({ error: "imageBase64 is required" });
    }

    let ext = "jpg";
    if (mimeType.includes("png")) ext = "png";
    if (mimeType.includes("webp")) ext = "webp";

    const buffer = Buffer.from(imageBase64, "base64");

    if (!buffer.length) {
      return res.status(400).json({ error: "Invalid image data" });
    }

    if (buffer.length > MAX_BYTES) {
      return res.status(400).json({ error: "Image too large (max 5 MB)" });
    }

    const filename = `${Date.now()}-${req.user.id.slice(0, 8)}.${ext}`;
    fs.writeFileSync(path.join(UPLOADS_DIR, filename), buffer);

    res.status(201).json({ imageUrl: `/uploads/${filename}` });
  })
);

module.exports = router;
