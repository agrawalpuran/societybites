const { serializeAdminOrder } = require("../lib/adminOrderDetail");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const seller = {
  id: "seller-1",
  name: "Anita Kitchen",
  phone: "919800000001",
  role: "seller",
  upiId: "anita@upi",
  upiDisplayName: "Anita",
  fulfilmentMode: "BOTH",
  hideFlatNumber: true,
  society: {
    id: "soc-seller",
    name: "Palm Heights",
    city: "Pune",
    address: "12 Palm Drive",
    state: "Maharashtra",
    pincode: "411001",
  },
  flat: { block: "B", flatNumber: "88", floor: 8, unit: "B" },
};

const buyer = {
  id: "buyer-1",
  name: "Ravi Shah",
  phone: "919800000002",
  role: "buyer",
  upiId: null,
  upiDisplayName: null,
  fulfilmentMode: "BUYER_PICKUP",
  hideFlatNumber: false,
  society: {
    id: "soc-buyer",
    name: "Lake View",
    city: "Pune",
    address: "4 Lake Road",
    state: "Maharashtra",
    pincode: "411002",
  },
  flat: { block: "A", flatNumber: "1204", floor: 12, unit: "A" },
};

const item = {
  id: "item-1",
  quantity: 2,
  unitPrice: 120,
  listing: {
    id: "listing-1",
    name: "Paneer tikka",
    sellerId: seller.id,
    pickupLocation: "My Home (Verified)",
    seller,
  },
};

const detail = serializeAdminOrder({
  id: "order-1",
  orderNumber: "SE-100001",
  status: "ready",
  type: "regular",
  paymentMethod: "upi",
  paymentStatus: "confirmed",
  subtotal: 240,
  communityFee: 0,
  deliveryCharge: 20,
  total: 260,
  fulfilmentMethod: "seller_delivery",
  deliveryCollectBy: "seller",
  fulfilmentNotes: "Leave with security",
  buyer,
  society: buyer.society,
  items: [item, { ...item, id: "item-2", quantity: 1, unitPrice: 80 }],
  couponRedemptions: [
    {
      status: "REVERSED",
      discountAmount: 10,
      coupon: { code: "OLD", name: "Old" },
    },
    {
      status: "REDEEMED",
      discountAmount: 40,
      coupon: { code: "WELCOME", name: "Welcome" },
    },
  ],
  createdAt: new Date("2026-10-23T08:00:00.000Z"),
  updatedAt: new Date("2026-10-23T09:00:00.000Z"),
  acceptedAt: new Date("2026-10-23T08:05:00.000Z"),
});

assert(detail.orderNumber === "SE-100001", "order number");
assert(detail.buyer.name === "Ravi Shah", "buyer name");
assert(detail.buyer.phone === "919800000002", "buyer phone");
assert(detail.buyer.flat.flatNumber === "1204", "buyer flat");
assert(detail.buyer.flat.block === "A", "buyer block");
assert(detail.buyer.society.address === "4 Lake Road", "buyer address");
assert(detail.buyer.society.pincode === "411002", "buyer pincode");
assert(detail.sellers.length === 1, "duplicate seller collapsed");
assert(detail.sellers[0].name === "Anita Kitchen", "seller name");
assert(detail.sellers[0].phone === "919800000001", "seller phone");
assert(detail.sellers[0].upiId === "anita@upi", "seller upi");
assert(detail.sellers[0].society.address === "12 Palm Drive", "seller address");
assert(detail.sellers[0].flat.flatNumber === "88", "admin still receives hidden flat");
assert(detail.sellers[0].hideFlatNumber === true, "hide flag kept for admin context");
assert(detail.items.length === 2, "both items kept");
assert(detail.items[0].lineTotal === 240, "line total");
assert(detail.items[0].listing.sellerName === "Anita Kitchen", "item seller");
assert(detail.coupon.code === "WELCOME", "live coupon preferred over reversed");
assert(detail.coupon.discountAmount === 40, "coupon amount");
assert(detail.fulfilmentNotes === "Leave with security", "fulfilment notes");
assert(detail.timeline.acceptedAt instanceof Date, "timeline kept");

const empty = serializeAdminOrder({
  id: "order-2",
  orderNumber: "SE-100002",
  status: "pending",
  subtotal: 0,
  communityFee: 0,
  total: 0,
  buyer: null,
  items: [],
  createdAt: new Date(),
  updatedAt: new Date(),
});
assert(empty.buyer === null, "missing buyer");
assert(empty.sellers.length === 0, "no sellers");
assert(empty.coupon === null, "no coupon");

console.log("admin order detail ok");
