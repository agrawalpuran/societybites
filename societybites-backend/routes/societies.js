const express = require("express");
const prisma = require("../lib/prisma");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");

const router = express.Router();

router.get(
  "/",
  asyncHandler(async (_req, res) => {
    const societies = await prisma.society.findMany({
      where: { status: "active" },
      orderBy: { name: "asc" },
    });
    res.json(societies);
  })
);

router.get(
  "/:id",
  asyncHandler(async (req, res) => {
    const society = await prisma.society.findUnique({
      where: { id: req.params.id },
      include: {
        blocks: { orderBy: { name: "asc" } },
      },
    });

    if (!society) {
      return res.status(404).json({ error: "Society not found" });
    }

    res.json(society);
  })
);

router.post(
  "/join",
  requireUser,
  asyncHandler(async (req, res) => {
    const { inviteCode, flatNumber } = req.body;

    if (!inviteCode || !flatNumber) {
      return res.status(400).json({ error: "inviteCode and flatNumber are required" });
    }

    const society = await prisma.society.findFirst({
      where: { inviteCode: { equals: inviteCode, mode: "insensitive" } },
    });

    if (!society) {
      return res.status(400).json({ error: "Invalid invite code" });
    }

    if (society.status !== "active") {
      return res.status(400).json({ error: "This society is not accepting new members" });
    }

    if (req.user.societyId) {
      return res.status(400).json({ error: "You are already a member of a society" });
    }

    const digits = String(flatNumber);

    if (digits.length !== 4) {
      return res.status(400).json({ error: "Flat number must be 4 digits" });
    }

    const blockMap = { 1: "A", 2: "B", 3: "C", 4: "D", 5: "E" };
    const blockDigit = parseInt(digits[0], 10);
    const block = blockMap[blockDigit];

    if (!block) {
      return res.status(400).json({ error: "Invalid block digit" });
    }

    let flat = await prisma.flat.findUnique({
      where: {
        societyId_flatNumber: {
          societyId: society.id,
          flatNumber: digits,
        },
      },
    });

    if (!flat) {
      flat = await prisma.flat.create({
        data: {
          societyId: society.id,
          flatNumber: digits,
          block,
          floor: parseInt(digits.substring(1, 3), 10),
          unit: digits[3],
        },
      });
    }

    const user = await prisma.user.update({
      where: { id: req.user.id },
      data: { societyId: society.id, flatId: flat.id },
      include: { society: true, flat: true },
    });

    res.json(user);
  })
);

router.post(
  "/:id/validate-flat",
  requireUser,
  asyncHandler(async (req, res) => {
    const { flatNumber } = req.body;

    if (!flatNumber) {
      return res.status(400).json({ error: "flatNumber is required" });
    }

    if (req.user.societyId && req.user.societyId !== req.params.id) {
      return res.status(403).json({ error: "You do not belong to this society" });
    }

    const society = await prisma.society.findUnique({
      where: { id: req.params.id },
    });

    if (!society) {
      return res.status(404).json({ error: "Society not found" });
    }

    let flat = await prisma.flat.findUnique({
      where: {
        societyId_flatNumber: {
          societyId: req.params.id,
          flatNumber: String(flatNumber),
        },
      },
    });

    if (!flat) {
      const blockMap = { 1: "A", 2: "B", 3: "C", 4: "D", 5: "E" };
      const digits = String(flatNumber);

      if (digits.length !== 4) {
        return res.status(400).json({ error: "Flat number must be 4 digits" });
      }

      const blockDigit = parseInt(digits[0], 10);
      const block = blockMap[blockDigit];

      if (!block) {
        return res.status(400).json({ error: "Invalid block digit" });
      }

      flat = await prisma.flat.create({
        data: {
          societyId: req.params.id,
          flatNumber: digits,
          block,
          floor: parseInt(digits.substring(1, 3), 10),
          unit: digits[3],
        },
      });
    }

    res.json({
      valid: true,
      flat,
      society,
      deliveryAddress: {
        society: society.name,
        block: flat.block,
        floor: flat.floor,
        unit: flat.unit,
        flatNumber: flat.flatNumber,
      },
    });
  })
);

module.exports = router;
