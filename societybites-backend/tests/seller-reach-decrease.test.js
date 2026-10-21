require("dotenv").config();
const {
  isReachDecrease,
  orderOutsideNewReach,
  effectiveBeyondRadiusKm,
} = require("../lib/sellerReachDecrease");
const { SELLING_REACH_LEVELS } = require("../lib/sellingReach");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function society(id, lat, lng) {
  return { id, latitude: lat, longitude: lng, city: "Bengaluru" };
}

function main() {
  const sellerSociety = society("seller-soc", 12.9716, 77.5946);
  const buyerNear = society("buyer-near", 12.9986, 77.5946);
  const buyerFar = society("buyer-far", 13.1066, 77.5946);

  const current = {
    sellingReachLevel: SELLING_REACH_LEVELS.BEYOND_SOCIETY,
    sellingReachRadiusKm: 10,
  };
  const smaller = {
    sellingReachLevel: SELLING_REACH_LEVELS.BEYOND_SOCIETY,
    sellingReachRadiusKm: 5,
  };
  const mySociety = {
    sellingReachLevel: SELLING_REACH_LEVELS.MY_SOCIETY,
    sellingReachRadiusKm: null,
  };

  assert(
    isReachDecrease(current, smaller, null, "Bengaluru"),
    "smaller radius is decrease"
  );
  assert(!isReachDecrease(current, current, null, "Bengaluru"), "same is not decrease");
  assert(
    isReachDecrease(current, mySociety, null, "Bengaluru"),
    "my society from beyond is decrease"
  );
  assert(
    effectiveBeyondRadiusKm(mySociety, null, "Bengaluru") === 0,
    "my society effective km 0"
  );

  const orderNear = { society: buyerNear, societyId: buyerNear.id };
  const orderFar = { society: buyerFar, societyId: buyerFar.id };
  const orderInSociety = { society: sellerSociety, societyId: sellerSociety.id };

  assert(
    !orderOutsideNewReach(orderInSociety, sellerSociety, 0),
    "in-society order never outside"
  );
  assert(
    !orderOutsideNewReach(orderNear, sellerSociety, 5),
    "near buyer within 5km"
  );
  assert(
    orderOutsideNewReach(orderFar, sellerSociety, 5),
    "far buyer outside 5km"
  );
  assert(
    orderOutsideNewReach(orderNear, sellerSociety, 0),
    "cross-society outside when my society only"
  );

  console.log("seller-reach-decrease.test.js passed");
}

main();
