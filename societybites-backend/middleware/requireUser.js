const prisma = require("../lib/prisma");
const { verifyToken } = require("../lib/jwt");

async function requireUser(req, res, next) {
  const authHeader = req.header("Authorization");

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return res.status(401).json({ error: "Missing or invalid Authorization header" });
  }

  const token = authHeader.slice(7);

  let payload;
  try {
    payload = verifyToken(token);
  } catch (err) {
    if (err.name === "TokenExpiredError") {
      return res.status(401).json({ error: "Token expired", code: "TOKEN_EXPIRED" });
    }
    return res.status(401).json({ error: "Invalid token" });
  }

  const user = await prisma.user.findUnique({ where: { id: payload.userId } });

  if (!user) {
    return res.status(401).json({ error: "User not found" });
  }

  if (user.suspended) {
    return res.status(403).json({ error: "Account suspended" });
  }

  req.user = user;
  next();
}

function requireJoinedSociety(req, res) {
  if (!req.user || !req.user.societyId) {
    res.status(400).json({
      error: "You must join a society first",
      code: "SOCIETY_REQUIRED",
    });
    return null;
  }
  return req.user.societyId;
}

module.exports = { requireUser, requireJoinedSociety };
