const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { getPlatformFee } = require("../lib/platformFee");
const { getForceUpdateConfig } = require("../lib/appForceUpdate");
const { refreshServingCities } = require("../lib/servingCities");
const { servingCityPayload } = require("../lib/launchCity");

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

module.exports = router;
