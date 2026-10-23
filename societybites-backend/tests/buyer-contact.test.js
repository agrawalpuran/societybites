const {
  canRevealBuyerContact,
  maskBuyerPhone,
  serializeBuyerContactForViewer,
} = require("../lib/buyerContact");
const { serializeOrder } = require("../utils/listingSerializer");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function order({
  status = "accepted",
  paymentMethod = "upi",
  paymentStatus = "seller_confirmed",
  fulfilmentMethod = "seller_delivery",
  completedAt = null,
  sellerId = "seller-1",
  viewerId = "seller-1",
  phone = "+917721874567",
} = {}) {
  return {
    id: "o1",
    buyerId: "buyer-1",
    status,
    paymentMethod,
    paymentStatus,
    fulfilmentMethod,
    completedAt,
    buyer: { phone, name: "Antara" },
    items: [
      {
        quantity: 1,
        unitPrice: 90,
        listing: { id: "l1", name: "Amla", sellerId, price: 90 },
      },
    ],
    _viewerId: viewerId,
  };
}

function run() {
  assert(maskBuyerPhone("+917721874567") === "+9177218•••••", "mask keeps prefix");
  assert(
    canRevealBuyerContact(order()) === true,
    "paid seller delivery can reveal"
  );
  assert(
    canRevealBuyerContact(order({ paymentStatus: "pending" })) === false,
    "unpaid UPI cannot reveal"
  );
  assert(
    canRevealBuyerContact(order({ paymentStatus: "buyer_marked_paid" })) === false,
    "buyer marked paid is not enough"
  );
  assert(
    canRevealBuyerContact(
      order({ paymentMethod: "cash", paymentStatus: "pending" })
    ) === true,
    "cash accepted can reveal"
  );
  assert(
    canRevealBuyerContact(order({ status: "pending" })) === false,
    "pending cannot reveal"
  );
  assert(
    canRevealBuyerContact(order({ fulfilmentMethod: "pickup" })) === false,
    "pickup cannot reveal"
  );
  assert(
    canRevealBuyerContact(
      order({
        status: "completed",
        completedAt: new Date(Date.now() - 3 * 60 * 60 * 1000),
      })
    ) === true,
    "completed seller delivery can still reveal"
  );

  const sellerView = serializeOrder(order(), { viewerUserId: "seller-1" });
  assert(sellerView.buyerPhone == null, "kitchen list omits raw phone");
  assert(sellerView.canRevealBuyerPhone === true, "seller can reveal");
  assert(sellerView.buyerPhoneMasked, "masked phone for seller");

  const unpaid = serializeOrder(order({ paymentStatus: "pending" }), {
    viewerUserId: "seller-1",
  });
  assert(unpaid.canRevealBuyerPhone === false, "unpaid flag");
  assert(unpaid.buyerPhone == null, "unpaid still omits raw phone");

  const buyerView = serializeOrder(order(), { viewerUserId: "buyer-1" });
  assert(buyerView.buyerPhone == null, "buyer payload omits phone field reuse");
  assert(buyerView.canRevealBuyerPhone === false, "buyer cannot reveal");

  const staffView = serializeBuyerContactForViewer(order(), "staff-1");
  assert(staffView.canRevealBuyerPhone === false, "staff cannot reveal");
  assert(staffView.buyerPhone == null, "staff does not get raw phone");

  console.log("buyer-contact.test.js ok");
}

run();
