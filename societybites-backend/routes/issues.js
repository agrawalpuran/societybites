const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { createIssueReport, listMyIssues, getOwnIssue } = require("../lib/issueReports");

const router = express.Router();

router.post(
  "/",
  requireUser,
  asyncHandler(async (req, res) => {
    const issue = await createIssueReport(req.body, req.user);
    res.status(201).json(issue);
  })
);

router.get(
  "/my",
  requireUser,
  asyncHandler(async (req, res) => {
    const issues = await listMyIssues(req.user.id);
    res.json({ issues });
  })
);

router.get(
  "/:id",
  requireUser,
  asyncHandler(async (req, res) => {
    const issue = await getOwnIssue(req.user.id, req.params.id);
    res.json(issue);
  })
);

module.exports = router;
