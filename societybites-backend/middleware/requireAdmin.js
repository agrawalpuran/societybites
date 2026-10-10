function canAccessAdminPortal(user) {
  if (!user) return false;
  if (user.role === "super_admin") return true;
  if (user.consoleAdmin === true) return true;
  // Legacy: role was overwritten before consoleAdmin existed.
  if (user.role === "admin") return true;
  return false;
}

/** View-only console (`consoleAdmin` / legacy `admin`) or full control (`super_admin`). */
function requireAdmin(req, res, next) {
  if (!canAccessAdminPortal(req.user)) {
    return res.status(403).json({ error: "Admin access required" });
  }
  next();
}

function requireSuperAdmin(req, res, next) {
  if (req.user.role !== "super_admin") {
    return res.status(403).json({ error: "Super admin access required" });
  }
  next();
}

module.exports = { requireAdmin, requireSuperAdmin, canAccessAdminPortal };
