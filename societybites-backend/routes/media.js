const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { uploadPublicImage } = require("../lib/objectStorage");
const { optimizeListingPhoto } = require("../lib/listingImageOptimize");
const {
  parseImageUpload,
  storagePrefixForPurpose,
} = require("../lib/profileImage");

const router = express.Router();

router.post(
  "/upload",
  requireUser,
  asyncHandler(async (req, res) => {
    const parsed = parseImageUpload(req.body);
    const prefix = storagePrefixForPurpose(req.body && req.body.purpose);
    let { buffer, mimeType } = parsed;
    if (prefix === "listings") {
      const optimized = await optimizeListingPhoto(buffer);
      buffer = optimized.buffer;
      mimeType = optimized.mimeType;
    }
    const imageUrl = await uploadPublicImage({
      buffer,
      mimeType,
      userId: req.user.id,
      prefix,
    });

    res.status(201).json({ imageUrl });
  })
);

module.exports = router;
