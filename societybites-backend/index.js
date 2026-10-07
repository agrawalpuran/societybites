const express = require("express");
const cors = require("cors");
const path = require("path");
require("dotenv").config();

const prisma = require("./lib/prisma");
const logger = require("./lib/logger");
const { setupSeedImages, UPLOADS_DIR, SEED_DIR } = require("./lib/setupSeedImages");
const { isObjectStorageConfigured } = require("./lib/objectStorage");
const { rateLimit } = require("./middleware/rateLimit");
const authRoutes = require("./routes/auth");
const societyRoutes = require("./routes/societies");
const listingRoutes = require("./routes/listings");
const orderRoutes = require("./routes/orders");
const paymentRoutes = require("./routes/payments");
const reviewRoutes = require("./routes/reviews");
const mediaRoutes = require("./routes/media");
const adminRoutes = require("./routes/admin");
const settingsRoutes = require("./routes/settings");
const deviceRoutes = require("./routes/devices");
const issueRoutes = require("./routes/issues");
const couponRoutes = require("./routes/coupons");
const fssaiRoutes = require("./routes/fssai");
const preorderCampaignRoutes = require("./routes/preorderCampaigns");

const app = express();
const PORT = process.env.PORT || 3000;

setupSeedImages();

function serveStaticWithCors(urlPath, directory) {
  app.use(
    urlPath,
    (_req, res, next) => {
      res.setHeader("Access-Control-Allow-Origin", "*");
      next();
    },
    express.static(directory)
  );
}

app.use(cors());
app.use(express.json({ limit: "8mb" }));
app.set("etag", false);

app.use((req, res, next) => {
  const path = req.path || "";
  if (path.startsWith("/uploads") || path.startsWith("/seed-images")) {
    return next();
  }
  res.setHeader("Cache-Control", "no-store");
  next();
});

app.use((_req, res, next) => {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("X-XSS-Protection", "1; mode=block");
  next();
});

app.use((req, res, next) => {
  const start = Date.now();
  res.on("finish", () => {
    const duration = Date.now() - start;
    if (req.path !== "/health" && req.path !== "/ready") {
      logger.info(
        "http",
        `${req.method} ${req.originalUrl} ${res.statusCode} ${duration}ms`
      );
    }
  });
  next();
});

serveStaticWithCors("/uploads", UPLOADS_DIR);
serveStaticWithCors("/seed-images", SEED_DIR);

app.get("/health", (_req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

app.get("/ready", async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;

    res.json({
      status: "ready",
      database: "connected"
    });
  } catch (e) {
    logger.error("server", "Ready check failed", {
      code: e && e.code,
      message: e && e.message,
    });

    res.status(503).json({
      status: "not_ready",
      database: "disconnected"
    });
  }
});

app.get("/", (_req, res) => {
  res.send("Backend running 🚀");
});

app.use("/auth", rateLimit({ windowMs: 60000, max: 20 }), authRoutes);
app.use("/societies", societyRoutes);
app.use("/listings", listingRoutes);
app.use("/preorder-campaigns", preorderCampaignRoutes);
app.use("/orders", orderRoutes);
app.use("/payments", paymentRoutes);
app.use("/reviews", reviewRoutes);
app.use("/media", mediaRoutes);
app.use("/admin", adminRoutes);
app.use("/settings", settingsRoutes);
app.use("/devices", deviceRoutes);
app.use("/issues", issueRoutes);
app.use("/coupons", couponRoutes);
app.use("/fssai", fssaiRoutes);

app.use((err, _req, res, _next) => {
  logger.error("server", err.message, { stack: err.stack });

  if (err.code === "P2002") {
    return res.status(409).json({ error: "Record already exists" });
  }
  if (err.code === "P2025") {
    return res.status(404).json({ error: "Record not found" });
  }
  if (
    err.name === "PrismaClientValidationError" ||
    (typeof err.message === "string" &&
      err.message.includes("Unknown field") &&
      err.message.includes("Prisma"))
  ) {
    return res.status(503).json({
      error:
        "API database client is out of date. Stop the server, run npx prisma generate in societybites-backend, then start the server again.",
      code: "PRISMA_CLIENT_STALE",
    });
  }

  const statusCode = err.statusCode || 500;
  const message = statusCode === 500 ? "Internal server error" : err.message;
  const payload = { error: message };
  if (
    typeof err.code === "string" &&
    err.code.length > 0 &&
    !err.code.startsWith("P")
  ) {
    payload.code = err.code;
  }
  if (err.availableQuantity !== undefined) {
    payload.availableQuantity = err.availableQuantity;
  }
  res.status(statusCode).json(payload);
});

const server = app.listen(PORT, () => {
  // Chrome reuses sockets longer than Node's 5s default and then reports
  // "Failed to fetch" when Node has already closed them.
  server.keepAliveTimeout = 65000;
  server.headersTimeout = 66000;
  logger.info("server", `Server running on port ${PORT}`);
  logger.info("server", `Serving uploads from ${UPLOADS_DIR}`);
  logger.info(
    "server",
    isObjectStorageConfigured()
      ? "Listing images use Supabase Storage"
      : "Listing images are not configured — set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY"
  );
});

let shuttingDown = false;
function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info("server", `${signal} received, shutting down`);
  server.close(() => {
    prisma
      .$disconnect()
      .catch(() => {})
      .finally(() => process.exit(0));
  });
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
