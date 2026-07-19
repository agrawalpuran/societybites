const express = require("express");
const prisma = require("../lib/prisma");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { serializeReview } = require("../utils/listingSerializer");

const router = express.Router();

router.get(
  "/listing/:listingId",
  asyncHandler(async (req, res) => {
    const reviews = await prisma.review.findMany({
      where: { listingId: req.params.listingId, hidden: false },
      include: { reviewer: { include: { flat: true } } },
      orderBy: { createdAt: "desc" },
    });

    res.json(reviews.map(serializeReview));
  })
);

router.post(
  "/",
  requireUser,
  asyncHandler(async (req, res) => {
    const { orderId, listingId, rating, comment, tags = [], wouldOrderAgain = true } =
      req.body;

    if (!orderId || !listingId || rating === undefined) {
      return res.status(400).json({
        error: "orderId, listingId, and rating are required",
      });
    }

    const parsedRating = parseInt(rating, 10);

    if (parsedRating < 1 || parsedRating > 5) {
      return res.status(400).json({ error: "rating must be between 1 and 5" });
    }

    const order = await prisma.order.findUnique({
      where: { id: orderId },
      include: { items: true },
    });

    if (!order) {
      return res.status(404).json({ error: "Order not found" });
    }

    if (order.buyerId !== req.user.id) {
      return res.status(403).json({ error: "Only the buyer can leave a review" });
    }

    if (order.status !== "completed") {
      return res.status(400).json({
        error: "Reviews are allowed only after the order is completed",
      });
    }

    const ownsListing = order.items.some((item) => item.listingId === listingId);

    if (!ownsListing) {
      return res.status(400).json({
        error: "This listing was not part of the order",
      });
    }

    const review = await prisma.review.create({
      data: {
        orderId,
        listingId,
        reviewerId: req.user.id,
        rating: parsedRating,
        comment,
        tags: Array.isArray(tags) ? tags : [],
        wouldOrderAgain: Boolean(wouldOrderAgain),
      },
      include: { reviewer: { include: { flat: true } } },
    });

    res.status(201).json(serializeReview(review));
  })
);

module.exports = router;
