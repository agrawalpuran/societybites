const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { getPlatformFee, resolvePlatformFee } = require("../lib/platformFee");
const { getForceUpdateConfig } = require("../lib/appForceUpdate");
const { refreshServingCities } = require("../lib/servingCities");
const { servingCityPayload } = require("../lib/launchCity");
const { requireUser } = require("../middleware/requireUser");

const router = express.Router();

router.get(
  "/",
  asyncHandler(async (_req, res) => {
    const [platformFee, forceUpdate, launch] = await Promise.all([
      getPlatformFee(),
      getForceUpdateConfig(),
      refreshServingCities(),
    ]);
    res.json({
      platformFee,
      minIosBuild: forceUpdate.minIosBuild,
      minAndroidBuild: forceUpdate.minAndroidBuild,
      iosUpdateUrl: forceUpdate.iosUpdateUrl,
      androidUpdateUrl: forceUpdate.androidUpdateUrl,
      ...servingCityPayload(launch),
    });
  })
);

router.get(
  "/platform-fee",
  requireUser,
  asyncHandler(async (req, res) => {
    const platformFee = await resolvePlatformFee({
      societyId: req.user.societyId,
    });
    res.json({ platformFee });
  })
);

module.exports = router;
