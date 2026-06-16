const prisma = require("../lib/prisma");

async function requireUser(req, res, next) {
  const userId = req.header("x-user-id");

  if (!userId) {
    return res.status(401).json({ error: "Missing x-user-id header" });
  }

  const user = await prisma.user.findUnique({ where: { id: userId } });

  if (!user) {
    return res.status(401).json({ error: "Invalid user" });
  }

  req.user = user;
  next();
}

module.exports = { requireUser };
