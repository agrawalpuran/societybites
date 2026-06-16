const express = require("express");
const cors = require("cors");
const path = require("path");
require("dotenv").config();

const prisma = require("./lib/prisma");
const { setupSeedImages, UPLOADS_DIR, SEED_DIR } = require("./lib/setupSeedImages");
const authRoutes = require("./routes/auth");
const societyRoutes = require("./routes/societies");
const listingRoutes = require("./routes/listings");
const orderRoutes = require("./routes/orders");
const reviewRoutes = require("./routes/reviews");
const mediaRoutes = require("./routes/media");

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
serveStaticWithCors("/uploads", UPLOADS_DIR);
serveStaticWithCors("/seed-images", SEED_DIR);

app.get("/", (_req, res) => {
  res.send("Backend running 🚀");
});

app.get("/test-db", async (_req, res) => {
  try {
    const users = await prisma.user.findMany();
    res.json(users);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.use("/auth", authRoutes);
app.use("/societies", societyRoutes);
app.use("/listings", listingRoutes);
app.use("/orders", orderRoutes);
app.use("/reviews", reviewRoutes);
app.use("/media", mediaRoutes);

app.use((err, _req, res, _next) => {
  console.error(err);

  if (err.code === "P2002") {
    return res.status(409).json({ error: "Record already exists" });
  }

  if (err.code === "P2025") {
    return res.status(404).json({ error: "Record not found" });
  }

  res.status(500).json({ error: err.message || "Internal server error" });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`Serving uploads from ${UPLOADS_DIR}`);
});
