const {
  ANDROID_CHANNEL_ID,
  buildFcmMessage,
  formatNotificationTime,
} = require("../utils/notifications");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const message = buildFcmMessage("x".repeat(40), {
  title: "Order confirmed",
  body: "Your order has been confirmed.",
  data: {
    type: "order_update",
    orderId: "ord-1",
    notificationType: "order_accepted",
  },
});

assert(message.notification.title === "Order confirmed", "title");
assert(message.android.priority === "high", "android priority");
assert(
  message.android.notification.channelId === ANDROID_CHANNEL_ID,
  "android channel id"
);
assert(ANDROID_CHANNEL_ID === "societybites_orders", "channel constant");
assert(message.data.notificationType === "order_accepted", "data type");
assert(message.apns.headers["apns-push-type"] === "alert", "apns push type");
assert(message.apns.headers["apns-priority"] === "10", "apns priority");
assert(message.apns.payload.aps.sound === "default", "apns sound");
assert(message.apns.payload.aps.alert.title === "Order confirmed", "apns title");

// 12:30 UTC is 6:00 PM IST. Host-local toLocaleString() would print the UTC clock.
assert(
  formatNotificationTime("2026-10-02T12:30:00.000Z") === "2 Oct, 6:00 PM",
  "ready time is IST"
);

console.log("notifications-payload.test.js passed");
