const { distanceKmBetweenCoordinates, isValidSocietyLocation } = require("./geoDistance");
const {
  SELLING_REACH_LEVELS,
  normalizeSellingReachLevel,
  resolveSellerAppliedRadiusKm,
} = require("./sellingReach");

const TERMINAL_ORDER_STATUSES = Object.freeze(["completed", "cancelled", "rejected"]);

function httpError(statusCode, message, extra = {}) {
  const err = new Error(message);
  err.statusCode = statusCode;
  Object.assign(err, extra);
  return err;
}

function effectiveBeyondRadiusKm(sellerReach, cityReachConfig, societyCity) {
  const level = normalizeSellingReachLevel(sellerReach.sellingReachLevel);
  if (level === SELLING_REACH_LEVELS.MY_SOCIETY) return 0;
  const km = resolveSellerAppliedRadiusKm(
    {
      sellingReachLevel: sellerReach.sellingReachLevel,
      sellingReachRadiusKm: sellerReach.sellingReachRadiusKm,
    },
    cityReachConfig,
    societyCity
  );
  return km == null ? 0 : Number(km);
}

function isReachDecrease(currentReach, proposedReach, cityReachConfig, societyCity) {
  const currentKm = effectiveBeyondRadiusKm(currentReach, cityReachConfig, societyCity);
  const proposedKm = effectiveBeyondRadiusKm(proposedReach, cityReachConfig, societyCity);
  return proposedKm < currentKm - 0.001;
}

function orderOutsideNewReach(order, sellerSociety, newBeyondRadiusKm) {
  const buyerSociety = order.society;
  if (!buyerSociety || !sellerSociety) return false;
  if (buyerSociety.id === sellerSociety.id) return false;
  if (newBeyondRadiusKm <= 0) return true;
  if (!isValidSocietyLocation(buyerSociety) || !isValidSocietyLocation(sellerSociety)) {
    return true;
  }
  const distanceKm = distanceKmBetweenCoordinates(buyerSociety, sellerSociety);
  if (distanceKm == null) return true;
  return distanceKm > newBeyondRadiusKm;
}

async function loadOpenOrdersForSeller(prisma, sellerId) {
  return prisma.order.findMany({
    where: {
      status: { notIn: [...TERMINAL_ORDER_STATUSES] },
      items: { some: { listing: { sellerId } } },
    },
    select: {
      id: true,
      orderNumber: true,
      status: true,
      societyId: true,
      society: {
        select: {
          id: true,
          latitude: true,
          longitude: true,
          city: true,
        },
      },
    },
  });
}

/**
 * @returns {{
 *   change: 'increase'|'same'|'decrease',
 *   allowed: boolean,
 *   isDecrease: boolean,
 *   openOrderCount: number,
 *   blockingOrderCount: number,
 *   requiresConfirmation: boolean,
 *   confirmationMessage: string|null,
 *   errorCode: string|null,
 *   message: string|null,
 * }}
 */
async function evaluateSellingReachChange({
  prisma,
  sellerId,
  sellerSociety,
  currentReach,
  proposedReach,
  cityReachConfig,
}) {
  const societyCity = sellerSociety && sellerSociety.city;
  const decrease = isReachDecrease(
    currentReach,
    proposedReach,
    cityReachConfig,
    societyCity
  );
  const currentKm = effectiveBeyondRadiusKm(currentReach, cityReachConfig, societyCity);
  const proposedKm = effectiveBeyondRadiusKm(proposedReach, cityReachConfig, societyCity);
  const change =
    proposedKm > currentKm + 0.001
      ? "increase"
      : decrease
        ? "decrease"
        : "same";

  const openOrders = await loadOpenOrdersForSeller(prisma, sellerId);
  const newBeyondKm = effectiveBeyondRadiusKm(proposedReach, cityReachConfig, societyCity);

  let blockingOrderCount = 0;
  for (const order of openOrders) {
    if (orderOutsideNewReach(order, sellerSociety, newBeyondKm)) {
      blockingOrderCount += 1;
    }
  }

  const confirmationMessage =
    "This only affects new buyers. Your current orders stay unchanged.";

  if (!decrease) {
    return {
      change,
      allowed: true,
      isDecrease: false,
      openOrderCount: openOrders.length,
      blockingOrderCount: 0,
      requiresConfirmation: false,
      confirmationMessage: null,
      errorCode: null,
      message: null,
    };
  }

  if (blockingOrderCount > 0) {
    const noun = blockingOrderCount === 1 ? "order" : "orders";
    return {
      change,
      allowed: false,
      isDecrease: true,
      openOrderCount: openOrders.length,
      blockingOrderCount,
      requiresConfirmation: false,
      confirmationMessage: null,
      errorCode: "REACH_DECREASE_BLOCKED",
      message:
        `You have ${blockingOrderCount} open ${noun} from buyers outside your new reach. ` +
        "Finish or cancel them before reducing how far you sell.",
    };
  }

  return {
    change,
    allowed: true,
    isDecrease: true,
    openOrderCount: openOrders.length,
    blockingOrderCount: 0,
    requiresConfirmation: openOrders.length > 0,
    confirmationMessage: openOrders.length > 0 ? confirmationMessage : null,
    errorCode: null,
    message: null,
  };
}

async function assertSellingReachDecreaseAllowed(options) {
  const evaluation = await evaluateSellingReachChange(options);
  if (!evaluation.allowed) {
    throw httpError(400, evaluation.message, {
      code: evaluation.errorCode,
      blockingOrderCount: evaluation.blockingOrderCount,
      openOrderCount: evaluation.openOrderCount,
    });
  }
  return evaluation;
}

module.exports = {
  TERMINAL_ORDER_STATUSES,
  effectiveBeyondRadiusKm,
  isReachDecrease,
  orderOutsideNewReach,
  evaluateSellingReachChange,
  assertSellingReachDecreaseAllowed,
};
