const express = require("express");
const prisma = require("../lib/prisma");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");

const router = express.Router();

function parseFloorUnit(flatNumber) {
  const digits = String(flatNumber).replace(/\D/g, "");
  if (digits.length >= 4) {
    return {
      floor: parseInt(digits.substring(1, 3), 10) || 0,
      unit: digits.slice(-1),
    };
  }
  if (digits.length >= 2) {
    return {
      floor: parseInt(digits.slice(0, -1), 10) || 0,
      unit: digits.slice(-1),
    };
  }
  return { floor: 0, unit: String(flatNumber).trim() || "1" };
}

router.get(
  "/",
  asyncHandler(async (_req, res) => {
    const societies = await prisma.society.findMany({
      where: { status: "active" },
      orderBy: { name: "asc" },
      include: {
        blocks: { orderBy: { name: "asc" } },
      },
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
    const { societyId, inviteCode, flatNumber, block, firstName, lastName } =
      req.body;

    if (!firstName || !String(firstName).trim()) {
      return res.status(400).json({ error: "First name is required" });
    }

    if (!flatNumber || !String(flatNumber).trim()) {
      return res.status(400).json({ error: "flatNumber is required" });
    }

    if (!block || !String(block).trim()) {
      return res.status(400).json({ error: "block is required" });
    }

    if (!societyId && !inviteCode) {
      return res.status(400).json({ error: "societyId or inviteCode is required" });
    }

    const fullName = [String(firstName).trim(), String(lastName || "").trim()]
      .filter(Boolean)
      .join(" ");

    if (req.user.societyId) {
      return res.status(400).json({ error: "You are already a member of a society" });
    }

    let society = null;

    if (societyId) {
      society = await prisma.society.findUnique({ where: { id: societyId } });
    } else if (inviteCode) {
      society = await prisma.society.findFirst({
        where: { inviteCode: { equals: inviteCode, mode: "insensitive" } },
      });
    }

    if (!society) {
      return res.status(400).json({
        error: societyId ? "Society not found" : "Invalid invite code",
      });
    }

    if (society.status !== "active") {
      return res.status(400).json({ error: "This society is not accepting new members" });
    }

    const flatDigits = String(flatNumber).trim();
    const blockValue = String(block).trim();
    const { floor, unit } = parseFloorUnit(flatDigits);

    let flat = await prisma.flat.findUnique({
      where: {
        societyId_flatNumber: {
          societyId: society.id,
          flatNumber: flatDigits,
        },
      },
    });

    if (!flat) {
      flat = await prisma.flat.create({
        data: {
          societyId: society.id,
          flatNumber: flatDigits,
          block: blockValue,
          floor,
          unit,
        },
      });
    } else if (flat.block !== blockValue) {
      flat = await prisma.flat.update({
        where: { id: flat.id },
        data: { block: blockValue },
      });
    }

    const user = await prisma.user.update({
      where: { id: req.user.id },
      data: { societyId: society.id, flatId: flat.id, name: fullName },
      include: { society: true, flat: true },
    });

    res.json(user);
  })
);

router.post(
  "/:id/validate-flat",
  requireUser,
  asyncHandler(async (req, res) => {
    const { flatNumber, block } = req.body;

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

    const flatDigits = String(flatNumber).trim();

    let flat = await prisma.flat.findUnique({
      where: {
        societyId_flatNumber: {
          societyId: req.params.id,
          flatNumber: flatDigits,
        },
      },
    });

    if (!flat) {
      const blockValue =
        block && String(block).trim()
          ? String(block).trim()
          : "A";
      const { floor, unit } = parseFloorUnit(flatDigits);

      flat = await prisma.flat.create({
        data: {
          societyId: req.params.id,
          flatNumber: flatDigits,
          block: blockValue,
          floor,
          unit,
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
