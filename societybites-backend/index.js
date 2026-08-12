const express = require("express");
const cors = require("cors");
const path = require("path");
require("dotenv").config();
console.log("DATABASE_URL:", process.env.DATABASE_URL);

const prisma = require("./lib/prisma");
const logger = require("./lib/logger");
const { setupSeedImages, UPLOADS_DIR, SEED_DIR } = require("./lib/setupSeedImages");
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
      logger.info("http", `${req.method} ${req.path} ${res.statusCode} ${duration}ms`);
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
    console.error("READY CHECK ERROR:", e);

    res.status(503).json({
      status: "not_ready",
      database: "disconnected",
      error: e.message,
      code: e.code
    });
  }
});

app.get("/", (_req, res) => {
  res.send("Backend running 🚀");
});

app.use("/auth", rateLimit({ windowMs: 60000, max: 20 }), authRoutes);
app.use("/societies", societyRoutes);
app.use("/listings", listingRoutes);
app.use("/orders", orderRoutes);
app.use("/payments", paymentRoutes);
app.use("/reviews", reviewRoutes);
app.use("/media", mediaRoutes);
app.use("/admin", adminRoutes);
app.use("/settings", settingsRoutes);

app.use((err, _req, res, _next) => {
  logger.error("server", err.message, { stack: err.stack });

  if (err.code === "P2002") {
    return res.status(409).json({ error: "Record already exists" });
  }
  if (err.code === "P2025") {
    return res.status(404).json({ error: "Record not found" });
  }

  const statusCode = err.statusCode || 500;
  const message = statusCode === 500 ? "Internal server error" : err.message;
  res.status(statusCode).json({ error: message });
});

app.listen(PORT, () => {
  logger.info("server", `Server running on port ${PORT}`);
  logger.info("server", `Serving uploads from ${UPLOADS_DIR}`);
});
