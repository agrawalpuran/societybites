const express = require("express");
const prisma = require("../lib/prisma");
const { asyncHandler } = require("../utils/asyncHandler");

const router = express.Router();

router.post(
  "/login",
  asyncHandler(async (req, res) => {
    const { phone } = req.body;

    if (!phone) {
      return res.status(400).json({ error: "phone is required" });
    }

    let user = await prisma.user.findUnique({ where: { phone } });

    if (!user) {
      user = await prisma.user.create({
        data: { phone, role: "buyer" },
      });
    }

    res.json(user);
  })
);

router.get(
  "/users/:id",
  asyncHandler(async (req, res) => {
    const user = await prisma.user.findUnique({
      where: { id: req.params.id },
      include: {
        society: true,
        flat: true,
      },
    });

    if (!user) {
      return res.status(404).json({ error: "User not found" });
    }

    res.json(user);
  })
);

router.patch(
  "/users/:id/profile",
  asyncHandler(async (req, res) => {
    const { name, role, societyId, flatId } = req.body;

    const user = await prisma.user.update({
      where: { id: req.params.id },
      data: {
        ...(name !== undefined && { name }),
        ...(role !== undefined && { role }),
        ...(societyId !== undefined && { societyId }),
        ...(flatId !== undefined && { flatId }),
      },
      include: {
        society: true,
        flat: true,
      },
    });

    res.json(user);
  })
);

module.exports = router;
