const express = require("express");
const flagsRouter = require("./routes/flags");
const adminFlagsRouter = require("./routes/adminFlags");
const adminRouter = require("./routes/adminCampaigns");
const eventsRouter = require("./routes/adminEvents");
const referralsRouter = require("./routes/referrals");
const adminReferralsRouter = require("./routes/adminReferrals");
const adminRewardsRouter = require("./routes/adminRewards");
const adminInsightsRouter = require("./routes/adminInsights");
const myRewardsRouter = require("./routes/myRewards");

/**
 * Isolated incentive engine. Mounted at /incentive.
 * Flags default off. Campaign configuration and event processing do not issue rewards.
 * Event routes do not hook registration, orders, payments, listings, or reviews.
 * Order qualification reads an order only while an admin-ingested event is processed.
 * Referral routes issue codes and record attribution.
 * Reward routes read and approve incentive rewards. Issuance stays off unless the issuance switch is exactly true.
 * PUT /incentive/admin/flags lets a super admin store master, referral, buyer referral, or seller referral. Missing rows stay off. Issuance, redemption, and promotional campaigns have no writer.
 * Caller reward routes use the JWT user id and ignore a user id in the query.
 * Product routes record seller activation, first publication, and qualifying-order events after their own transactions commit. A failed incentive write does not change the product response.
 */
const router = express.Router();
router.use(flagsRouter);
router.use("/admin", adminFlagsRouter);
router.use("/admin", adminRouter);
router.use("/admin", eventsRouter);
router.use("/admin", adminReferralsRouter);
router.use("/admin", adminRewardsRouter);
router.use("/admin", adminInsightsRouter);
router.use(referralsRouter);
router.use(myRewardsRouter);

module.exports = router;
