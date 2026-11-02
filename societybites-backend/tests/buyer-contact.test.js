const {
  canRevealBuyerContact,
  canRevealSellerContact,
  maskBuyerPhone,
  serializeBuyerContactForViewer,
  serializeSellerContactForViewer,
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
  sellerPhone = "+919845154070",
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
        listing: {
          id: "l1",
          name: "Amla",
          sellerId,
          price: 90,
          seller: { id: sellerId, phone: sellerPhone, name: "Anita" },
        },
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
    canRevealBuyerContact(order({ fulfilmentMethod: "pickup" })) === true,
    "paid pickup can reveal for call"
  );
  assert(
    canRevealSellerContact(order({ fulfilmentMethod: "pickup" })) === true,
    "buyer can call kitchen on paid pickup"
  );
  assert(
    canRevealSellerContact(order({ paymentStatus: "pending" })) === false,
    "buyer cannot call on unpaid UPI"
  );
  assert(
    canRevealBuyerContact(
      order({
        status: "completed",
        completedAt: new Date(Date.now() - 3 * 60 * 60 * 1000),
      })
    ) === true,
    "completed order can still reveal"
  );

  const sellerView = serializeOrder(order(), { viewerUserId: "seller-1" });
  assert(sellerView.buyerPhone == null, "kitchen list omits raw phone");
  assert(sellerView.canRevealBuyerPhone === true, "seller can reveal");
  assert(sellerView.buyerPhoneMasked, "masked phone for seller");
  assert(sellerView.sellerPhone == null, "kitchen does not get own number");
  assert(sellerView.canRevealSellerPhone === false, "seller cannot reveal kitchen");

  const unpaid = serializeOrder(order({ paymentStatus: "pending" }), {
    viewerUserId: "seller-1",
  });
  assert(unpaid.canRevealBuyerPhone === false, "unpaid flag");
  assert(unpaid.buyerPhone == null, "unpaid still omits raw phone");

  const buyerView = serializeOrder(order(), { viewerUserId: "buyer-1" });
  assert(buyerView.buyerPhone == null, "buyer payload omits phone field reuse");
  assert(buyerView.canRevealBuyerPhone === false, "buyer cannot reveal");
  assert(buyerView.sellerPhone == null, "buyer list omits raw kitchen phone");
  assert(buyerView.canRevealSellerPhone === true, "buyer can call kitchen");
  assert(buyerView.sellerPhoneMasked, "masked kitchen phone for buyer");

  const unpaidBuyer = serializeOrder(order({ paymentStatus: "pending" }), {
    viewerUserId: "buyer-1",
  });
  assert(
    unpaidBuyer.canRevealSellerPhone === false,
    "unpaid buyer cannot call kitchen"
  );

  const staffView = serializeBuyerContactForViewer(order(), "staff-1");
  assert(staffView.canRevealBuyerPhone === false, "staff cannot reveal");
  assert(staffView.buyerPhone == null, "staff does not get raw phone");
  const staffSeller = serializeSellerContactForViewer(order(), "staff-1");
  assert(staffSeller.canRevealSellerPhone === false, "staff cannot call kitchen");
  assert(staffSeller.sellerPhone == null, "staff does not get kitchen phone");

  console.log("buyer-contact.test.js ok");
}

run();
