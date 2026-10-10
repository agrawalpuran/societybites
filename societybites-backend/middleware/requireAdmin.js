const ADMIN_PORTAL_ROLES = new Set(["admin", "super_admin"]);

/** View-only console (`admin`) or full control (`super_admin`). */
function requireAdmin(req, res, next) {
  if (!ADMIN_PORTAL_ROLES.has(req.user.role)) {
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

module.exports = { requireAdmin, requireSuperAdmin };
