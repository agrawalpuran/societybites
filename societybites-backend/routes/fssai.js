const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const {
  getMyFssai,
  uploadMyFssaiDocument,
  submitMyFssai,
  getMyFssaiDocumentUrl,
  requestFssaiAssistance,
} = require("../lib/fssaiCompliance");

const router = express.Router();

router.get(
  "/me",
  requireUser,
  asyncHandler(async (req, res) => {
    const fssai = await getMyFssai(req.user);
    res.json({ fssai });
  })
);

router.post(
  "/me/document",
  requireUser,
  asyncHandler(async (req, res) => {
    const result = await uploadMyFssaiDocument(req.user, req.body);
    res.status(201).json(result);
  })
);

router.post(
  "/me/submit",
  requireUser,
  asyncHandler(async (req, res) => {
    const fssai = await submitMyFssai(req.user, req.body);
    res.json({ fssai });
  })
);

router.get(
  "/me/document-url",
  requireUser,
  asyncHandler(async (req, res) => {
    const payload = await getMyFssaiDocumentUrl(req.user);
    res.json(payload);
  })
);

router.post(
  "/me/assistance",
  requireUser,
  asyncHandler(async (req, res) => {
    const request = await requestFssaiAssistance(req.user);
    res.status(201).json({ request });
  })
);

module.exports = router;
