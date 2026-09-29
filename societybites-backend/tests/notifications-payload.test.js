const { ANDROID_CHANNEL_ID, buildFcmMessage } = require("../utils/notifications");

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
assert(message.apns.headers["apns-priority"] === "10", "apns priority");
assert(message.apns.payload.aps.sound === "default", "apns sound");
assert(message.apns.payload.aps.alert.title === "Order confirmed", "apns title");

console.log("notifications-payload.test.js passed");
