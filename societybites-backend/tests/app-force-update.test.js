const assert = require("assert");
const {
  emptyConfig,
  getForceUpdateConfig,
  setForceUpdateConfig,
  MIN_IOS_BUILD_KEY,
  MIN_ANDROID_BUILD_KEY,
} = require("../lib/appForceUpdate");
const prisma = require("../lib/prisma");

async function main() {
  const before = {
    ios: await prisma.appSetting.findUnique({ where: { key: MIN_IOS_BUILD_KEY } }),
    android: await prisma.appSetting.findUnique({
      where: { key: MIN_ANDROID_BUILD_KEY },
    }),
  };

  try {
    const empty = emptyConfig();
    assert(empty.minIosBuild === 0, "default ios min is 0");
    assert(empty.minAndroidBuild === 0, "default android min is 0");

    const updated = await setForceUpdateConfig({
      minIosBuild: 50,
      minAndroidBuild: 48,
      iosUpdateUrl: "https://example.com/ios",
      androidUpdateUrl: "https://example.com/android",
    });
    assert(updated.minIosBuild === 50, "ios min saved");
    assert(updated.minAndroidBuild === 48, "android min saved");
    assert(updated.iosUpdateUrl === "https://example.com/ios", "ios url");
    assert(
      updated.androidUpdateUrl === "https://example.com/android",
      "android url"
    );

    const read = await getForceUpdateConfig({ bypassCache: true });
    assert(read.minIosBuild === 50, "read ios min");
    assert(read.minAndroidBuild === 48, "read android min");

    let rejected = false;
    try {
      await setForceUpdateConfig({ minIosBuild: -1 });
    } catch (err) {
      rejected = err.statusCode === 400;
    }
    assert(rejected, "negative min build rejected");

    console.log("app-force-update.test.js passed");
  } finally {
    if (before.ios) {
      await prisma.appSetting.update({
        where: { key: MIN_IOS_BUILD_KEY },
        data: { value: before.ios.value },
      });
    } else {
      await prisma.appSetting.deleteMany({ where: { key: MIN_IOS_BUILD_KEY } });
    }
    if (before.android) {
      await prisma.appSetting.update({
        where: { key: MIN_ANDROID_BUILD_KEY },
        data: { value: before.android.value },
      });
    } else {
      await prisma.appSetting.deleteMany({
        where: { key: MIN_ANDROID_BUILD_KEY },
      });
    }
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
