const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { uploadPublicImage } = require("../lib/objectStorage");
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
    const imageUrl = await uploadPublicImage({
      buffer: parsed.buffer,
      mimeType: parsed.mimeType,
      userId: req.user.id,
      prefix: storagePrefixForPurpose(req.body && req.body.purpose),
    });

    res.status(201).json({ imageUrl });
  })
);

module.exports = router;
