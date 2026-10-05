const prisma = require("./prisma");

function money(value) {
  return Math.round(Number(value) * 100) / 100;
}

function sellerFromOrder(order) {
  const listing = order?.items?.[0]?.listing;
  const seller = listing?.seller;
  return {
    sellerId: seller?.id || listing?.sellerId || null,
    sellerName: seller?.name || null,
    sellerPhone: seller?.phone || null,
  };
}

function parseDate(value, endOfDay) {
  if (!value) return null;
  const date = new Date(String(value));
  if (Number.isNaN(date.getTime())) return null;
  if (endOfDay) {
    date.setUTCHours(23, 59, 59, 999);
  }
  return date;
}

async function listCouponSellerPayouts({ dateFrom, dateTo, sellerId, db = prisma }) {
  const from = parseDate(dateFrom, false);
  const to = parseDate(dateTo, true);

  const orderFilter = {
    status: { not: "cancelled" },
    ...(from || to
      ? {
          createdAt: {
            ...(from && { gte: from }),
            ...(to && { lte: to }),
          },
        }
      : {}),
    ...(sellerId
      ? { items: { some: { listing: { sellerId: String(sellerId) } } } }
      : {}),
  };

  const redemptions = await db.couponRedemption.findMany({
    where: {
      status: "REDEEMED",
      order: { is: orderFilter },
    },
    include: {
      coupon: { select: { code: true } },
      order: {
        select: {
          id: true,
          orderNumber: true,
          createdAt: true,
          subtotal: true,
          total: true,
          status: true,
          paymentStatus: true,
          items: {
            take: 1,
            orderBy: { id: "asc" },
            include: {
              listing: {
                select: {
                  sellerId: true,
                  seller: { select: { id: true, name: true, phone: true } },
                },
              },
            },
          },
        },
      },
    },
    orderBy: [{ redeemedAt: "desc" }, { createdAt: "desc" }],
  });

  const rows = redemptions
    .filter((row) => row.order)
    .map((row) => {
      const seller = sellerFromOrder(row.order);
      return {
        orderId: row.order.id,
        orderNumber: row.order.orderNumber,
        createdAt: row.order.createdAt,
        redeemedAt: row.redeemedAt,
        sellerId: seller.sellerId,
        sellerName: seller.sellerName,
        sellerPhone: seller.sellerPhone,
        couponCode: row.coupon.code,
        foodSubtotal: money(row.order.subtotal),
        buyerPaid: money(row.order.total),
        subsidyAmount: money(row.discountAmount),
        orderStatus: row.order.status,
        paymentStatus: row.order.paymentStatus,
      };
    });

  const bySellerMap = new Map();
  for (const row of rows) {
    const key = row.sellerId || "unknown";
    const current = bySellerMap.get(key) || {
      sellerId: row.sellerId,
      sellerName: row.sellerName,
      sellerPhone: row.sellerPhone,
      subsidyTotal: 0,
      orderCount: 0,
    };
    current.subsidyTotal = money(current.subsidyTotal + row.subsidyAmount);
    current.orderCount += 1;
    if (!current.sellerName && row.sellerName) current.sellerName = row.sellerName;
    if (!current.sellerPhone && row.sellerPhone) current.sellerPhone = row.sellerPhone;
    bySellerMap.set(key, current);
  }

  const bySeller = Array.from(bySellerMap.values()).sort(
    (a, b) => b.subsidyTotal - a.subsidyTotal
  );
  const totalSubsidy = money(rows.reduce((sum, row) => sum + row.subsidyAmount, 0));

  return {
    totalSubsidy,
    rowCount: rows.length,
    rows,
    bySeller,
  };
}

module.exports = {
  listCouponSellerPayouts,
};
