/**
 * Send a real push to registered devices using the same payload the app sends.
 * Verifies Firebase Admin -> FCM -> APNs/Android without building the app.
 *
 *   node scripts/send-test-push.js            # every active device
 *   node scripts/send-test-push.js ios        # iOS only
 *   node scripts/send-test-push.js android
 *
 * Device tokens are never printed.
 */
const prisma = require("../lib/prisma");
const { getMessaging } = require("../lib/firebase");
const { buildFcmMessage } = require("../utils/notifications");

const platform = (process.argv[2] || "").trim().toLowerCase();

async function main() {
  const devices = await prisma.deviceToken.findMany({
    where: { active: true, ...(platform ? { platform } : {}) },
    select: { id: true, token: true, platform: true, lastSeenAt: true },
    orderBy: { lastSeenAt: "desc" },
  });

  if (devices.length === 0) {
    console.log(`No active device tokens${platform ? ` for ${platform}` : ""}.`);
    return;
  }

  console.log(`Sending to ${devices.length} device(s)...\n`);

  for (const device of devices) {
    const message = buildFcmMessage(device.token, {
      title: "SocietyEats test",
      body: "If you can see this, push delivery is working.",
      data: {
        type: "order_update",
        orderId: "diagnostic",
        notificationType: "order_accepted",
      },
    });

    const seen = device.lastSeenAt
      ? new Date(device.lastSeenAt).toISOString()
      : "never";
    try {
      const startedAt = Date.now();
      await getMessaging().send(message);
      const clock = new Date().toLocaleTimeString("en-IN", {
        timeZone: "Asia/Kolkata",
      });
      console.log(
        `  OK      ${device.platform.padEnd(8)} accepted at ${clock} ` +
          `(${Date.now() - startedAt}ms), last seen ${seen}`
      );
    } catch (err) {
      console.log(
        `  FAILED  ${device.platform.padEnd(8)} last seen ${seen}` +
          `\n          ${err.code || ""} ${err.message || err}`
      );
    }
  }

  console.log("\nOK means FCM accepted it. Check the handset to confirm delivery.");
}

main()
  .catch((err) => {
    console.error("Test push failed:", err.message || err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
