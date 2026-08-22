const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { MAX_BYTES, uploadPublicImage } = require("../lib/objectStorage");

const router = express.Router();

router.post(
  "/upload",
  requireUser,
  asyncHandler(async (req, res) => {
    const { imageBase64, mimeType = "image/jpeg" } = req.body;

    if (!imageBase64) {
      return res.status(400).json({ error: "imageBase64 is required" });
    }

    const buffer = Buffer.from(imageBase64, "base64");
    if (!buffer.length) {
      return res.status(400).json({ error: "Invalid image data" });
    }
    if (buffer.length > MAX_BYTES) {
      return res.status(400).json({ error: "Image too large (max 5 MB)" });
    }

    const imageUrl = await uploadPublicImage({
      buffer,
      mimeType,
      userId: req.user.id,
      prefix: "listings",
    });

    res.status(201).json({ imageUrl });
  })
);

module.exports = router;
