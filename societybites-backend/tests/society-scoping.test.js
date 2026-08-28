require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const authRoutes = require("../routes/auth");
const listingRoutes = require("../routes/listings");
const campaignRoutes = require("../routes/preorderCampaigns");

const BUYER_PHONE = "+919845154070";
const OTHER_SOCIETY_ID = "brigade-gateway";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function jsonRequest(server, { method, path, token, body }) {
  const addr = server.address();
  return new Promise((resolve, reject) => {
    const payload = body ? Buffer.from(JSON.stringify(body)) : null;
    const req = http.request(
      {
        hostname: "127.0.0.1",
        port: addr.port,
        path,
        method,
        headers: {
          Accept: "application/json",
          ...(payload && {
            "Content-Type": "application/json",
            "Content-Length": String(payload.length),
          }),
          ...(token && { Authorization: `Bearer ${token}` }),
        },
      },
      (res) => {
        let data = "";
        res.on("data", (c) => (data += c));
        res.on("end", () => {
          let json = null;
          try {
            json = data ? JSON.parse(data) : null;
          } catch (_) {}
          resolve({ status: res.statusCode, json });
        });
      }
    );
    req.on("error", reject);
    if (payload) req.write(payload);
    req.end();
  });
}

async function main() {
  const buyer = await prisma.user.findUnique({ where: { phone: BUYER_PHONE } });
  assert(buyer && buyer.societyId, "Seed buyer with a society must exist");
  assert(
    buyer.societyId !== OTHER_SOCIETY_ID,
    "Seed buyer must not belong to the other test society"
  );

  const otherSociety = await prisma.society.findUnique({
    where: { id: OTHER_SOCIETY_ID },
  });
  assert(otherSociety, `Society ${OTHER_SOCIETY_ID} must exist from seed`);

  const buyerToken = signToken(buyer);
  const created = { listingIds: [], userIds: [] };

  const app = express();
  app.use(express.json());
  app.use("/auth", authRoutes);
  app.use("/listings", listingRoutes);
  app.use("/preorder-campaigns", campaignRoutes);
  app.use((err, _req, res, _next) => {
    const statusCode = err.statusCode || 500;
    res.status(statusCode).json({
      error: statusCode === 500 ? "Internal server error" : err.message,
    });
  });

  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  try {
    const unauthListings = await jsonRequest(server, {
      method: "GET",
      path: `/listings?societyId=${encodeURIComponent(OTHER_SOCIETY_ID)}`,
    });
    assert(unauthListings.status === 401, "unauthenticated listings GET must be 401");

    const unauthCampaigns = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns?societyId=${encodeURIComponent(OTHER_SOCIETY_ID)}`,
    });
    assert(unauthCampaigns.status === 401, "unauthenticated campaign GET must be 401");

    const otherListing = await prisma.listing.create({
      data: {
        sellerId: buyer.id,
        societyId: OTHER_SOCIETY_ID,
        name: `Other-society catalog ${Date.now()}`,
        price: 99,
        quantity: 1,
        status: "active",
      },
    });
    created.listingIds.push(otherListing.id);

    const listings = await jsonRequest(server, {
      method: "GET",
      path: `/listings?societyId=${encodeURIComponent(OTHER_SOCIETY_ID)}`,
      token: buyerToken,
    });
    assert(listings.status === 200, `authenticated listings GET failed: ${listings.status}`);
    assert(
      !listings.json.some((item) => item.id === otherListing.id),
      "authenticated user must not receive another society's listings"
    );
    assert(
      listings.json.every((item) => item.societyId === buyer.societyId),
      "listing catalog must be scoped to the authenticated user's society"
    );

    const otherDetail = await jsonRequest(server, {
      method: "GET",
      path: `/listings/${otherListing.id}`,
      token: buyerToken,
    });
    assert(otherDetail.status === 404, "other-society listing detail must be hidden");

    const campaigns = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns?societyId=${encodeURIComponent(OTHER_SOCIETY_ID)}`,
      token: buyerToken,
    });
    assert(campaigns.status === 200, "authenticated campaign GET failed");
    assert(
      campaigns.json.every((item) => item.societyId === buyer.societyId),
      "campaign catalog must be scoped to the authenticated user's society"
    );

    const patched = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: buyerToken,
      body: { societyId: OTHER_SOCIETY_ID },
    });
    assert(patched.status === 200, "profile patch should still succeed for other fields");
    const refreshed = await prisma.user.findUnique({ where: { id: buyer.id } });
    assert(
      refreshed.societyId === buyer.societyId,
      "PATCH /auth/me/profile must not change societyId"
    );

    const orphan = await prisma.user.create({
      data: {
        phone: `+9198${String(Date.now()).slice(-8)}`,
        role: "buyer",
      },
    });
    created.userIds.push(orphan.id);
    const orphanToken = signToken(orphan);
    const orphanCatalog = await jsonRequest(server, {
      method: "GET",
      path: "/listings",
      token: orphanToken,
    });
    assert(
      orphanCatalog.status === 400,
      "user without a society must not receive a catalog"
    );
  } finally {
    await prisma.listing.deleteMany({ where: { id: { in: created.listingIds } } });
    await prisma.user.deleteMany({ where: { id: { in: created.userIds } } });
    await new Promise((resolve) => server.close(resolve));
  }
}

main()
  .then(() => {
    console.log("society-scoping tests passed");
    process.exit(0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
