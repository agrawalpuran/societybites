const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { getPlatformFee } = require("../lib/platformFee");
const { getForceUpdateConfig } = require("../lib/appForceUpdate");

const router = express.Router();

router.get(
  "/",
  asyncHandler(async (_req, res) => {
    const [platformFee, forceUpdate] = await Promise.all([
      getPlatformFee(),
      getForceUpdateConfig(),
    ]);
    res.json({
      platformFee,
      minIosBuild: forceUpdate.minIosBuild,
      minAndroidBuild: forceUpdate.minAndroidBuild,
      iosUpdateUrl: forceUpdate.iosUpdateUrl,
      androidUpdateUrl: forceUpdate.androidUpdateUrl,
    });
  })
);

module.exports = router;
