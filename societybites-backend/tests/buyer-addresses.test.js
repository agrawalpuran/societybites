require("dotenv").config();

const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const authRoutes = require("../routes/auth");
const listingRoutes = require("../routes/listings");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function jsonRequest(server, { method, path, token, body }) {
  const addr = server.address();
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : Buffer.from(JSON.stringify(body));
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
        res.on("data", (chunk) => (data += chunk));
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
  const stamp = String(Date.now());
  const societyA = await prisma.society.create({
    data: {
      name: `Home Society ${stamp}`,
      city: "Bengaluru",
      inviteCode: `HM${stamp.slice(-8)}`,
    },
  });
  const societyB = await prisma.society.create({
    data: {
      name: `Office Society ${stamp}`,
      city: "Bengaluru",
      inviteCode: `OF${stamp.slice(-8)}`,
    },
  });
  const flatA = await prisma.flat.create({
    data: {
      societyId: societyA.id,
      flatNumber: "3062",
      block: "A",
      floor: 6,
      unit: "2",
    },
  });
  const buyer = await prisma.user.create({
    data: {
      phone: `+9188${stamp.slice(-8)}1`,
      name: "Address Buyer",
      role: "buyer",
      societyId: societyA.id,
      flatId: flatA.id,
    },
  });
  const seller = await prisma.user.create({
    data: {
      phone: `+9188${stamp.slice(-8)}2`,
      name: "Address Seller",
      role: "seller",
      societyId: societyA.id,
      flatId: flatA.id,
    },
  });
  const kitchen = await prisma.user.create({
    data: {
      phone: `+9188${stamp.slice(-8)}3`,
      name: "Office Kitchen",
      role: "seller",
      societyId: societyB.id,
    },
  });
  const listing = await prisma.listing.create({
    data: {
      sellerId: kitchen.id,
      societyId: societyB.id,
      name: `Office special ${stamp}`,
      price: 120,
      quantity: 2,
      status: "active",
    },
  });

  const app = express();
  app.use(express.json());
  app.use("/auth", authRoutes);
  app.use("/listings", listingRoutes);
  app.use((err, _req, res, _next) => {
    res.status(err.statusCode || 500).json({
      error: err.statusCode ? err.message : "Internal server error",
    });
  });
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  const buyerToken = signToken(buyer);
  const sellerToken = signToken(seller);
  let admin = null;
  let superAdmin = null;

  try {
    const listed = await jsonRequest(server, {
      method: "GET",
      path: "/auth/me/addresses",
      token: buyerToken,
    });
    assert(listed.status === 200, `list failed: ${listed.status} ${JSON.stringify(listed.json)}`);
    assert(listed.json.addresses.length === 1, "current society is saved as Home");
    assert(listed.json.addresses[0].label === "Home", "first place is named Home");
    assert(listed.json.addresses[0].selected === true, "Home starts selected");
    assert(listed.json.addresses[0].societyId === societyA.id, "Home keeps the joined society");

    const sellerList = await jsonRequest(server, {
      method: "GET",
      path: "/auth/me/addresses",
      token: sellerToken,
    });
    assert(sellerList.status === 403, "seller cannot use saved places");

    const added = await jsonRequest(server, {
      method: "POST",
      path: "/auth/me/addresses",
      token: buyerToken,
      body: { label: "Office", societyId: societyB.id },
    });
    assert(added.status === 201, `add failed: ${added.status} ${JSON.stringify(added.json)}`);
    assert(added.json.addresses.length === 2, "office is added beside home");
    const office = added.json.addresses.find((row) => row.label === "Office");
    const home = added.json.addresses.find((row) => row.label === "Home");
    assert(office && office.selected === false, "a new place is not selected");
    assert(home && home.selected === true, "home stays selected after saving office");

    const stillHome = await prisma.user.findUnique({ where: { id: buyer.id } });
    assert(stillHome.societyId === societyA.id, "saving a place does not move the buyer");
    assert(stillHome.flatId === flatA.id, "saving a place keeps the current flat");

    const before = await jsonRequest(server, {
      method: "GET",
      path: "/listings?status=active",
      token: buyerToken,
    });
    assert(before.status === 200, "listings before switch");
    assert(
      !before.json.some((item) => item.id === listing.id),
      "office food is hidden while home is selected"
    );

    const selected = await jsonRequest(server, {
      method: "POST",
      path: `/auth/me/addresses/${office.id}/select`,
      token: buyerToken,
    });
    assert(selected.status === 200, `select failed: ${selected.status} ${JSON.stringify(selected.json)}`);
    assert(selected.json.place.societyId === societyB.id, "selected place becomes the buyer society");
    assert(selected.json.place.flatId == null, "a place without a flat clears the flat");
    assert(
      selected.json.addresses.find((row) => row.id === office.id).selected === true,
      "office radio is filled"
    );
    assert(
      selected.json.addresses.find((row) => row.id === home.id).selected === false,
      "home radio is cleared"
    );

    const moved = await prisma.user.findUnique({ where: { id: buyer.id } });
    assert(moved.societyId === societyB.id, "buyer society follows the selected place");
    assert(moved.flatId == null, "buyer flat is cleared for a place without a door");

    const after = await jsonRequest(server, {
      method: "GET",
      path: "/listings?status=active",
      token: buyerToken,
    });
    assert(after.status === 200, "listings after switch");
    assert(
      after.json.some((item) => item.id === listing.id),
      "food follows the selected society"
    );

    const removedHome = await jsonRequest(server, {
      method: "DELETE",
      path: `/auth/me/addresses/${home.id}`,
      token: buyerToken,
    });
    assert(removedHome.status === 200, "an unselected place can be removed");
    assert(removedHome.json.addresses.length === 1, "office remains");

    const removedCurrent = await jsonRequest(server, {
      method: "DELETE",
      path: `/auth/me/addresses/${office.id}`,
      token: buyerToken,
    });
    assert(removedCurrent.status === 400, "the selected place cannot be removed");

    const sellerAdd = await jsonRequest(server, {
      method: "POST",
      path: "/auth/me/addresses",
      token: sellerToken,
      body: { label: "Other", societyId: societyB.id },
    });
    assert(sellerAdd.status === 403, "seller cannot add a place");
    const sellerRow = await prisma.user.findUnique({ where: { id: seller.id } });
    assert(sellerRow.societyId === societyA.id, "seller society stays put");

    admin = await prisma.user.create({
      data: {
        phone: `+9188${stamp.slice(-8)}4`,
        name: "Address Admin",
        role: "admin",
        societyId: societyA.id,
      },
    });
    superAdmin = await prisma.user.create({
      data: {
        phone: `+9188${stamp.slice(-8)}5`,
        name: "Address Super Admin",
        role: "super_admin",
        societyId: societyA.id,
      },
    });
    for (const account of [admin, superAdmin]) {
      const addedPlace = await jsonRequest(server, {
        method: "POST",
        path: "/auth/me/addresses",
        token: signToken(account),
        body: { label: "Office", societyId: societyB.id },
      });
      assert(addedPlace.status === 201, `${account.role} can save a place`);
      const office = addedPlace.json.addresses.find((row) => row.label === "Office");
      const selected = await jsonRequest(server, {
        method: "POST",
        path: `/auth/me/addresses/${office.id}/select`,
        token: signToken(account),
      });
      assert(selected.status === 200, `${account.role} can select a place`);
      const row = await prisma.user.findUnique({ where: { id: account.id } });
      assert(row.societyId === societyB.id, `${account.role} address changes when selected`);
    }

    console.log("buyer address tests passed");
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await prisma.listing.deleteMany({ where: { id: listing.id } });
    const userIds = [buyer.id, seller.id, kitchen.id, admin && admin.id, superAdmin && superAdmin.id].filter(Boolean);
    await prisma.buyerAddress.deleteMany({
      where: { userId: { in: userIds } },
    });
    await prisma.user.deleteMany({
      where: { id: { in: userIds } },
    });
    await prisma.flat.deleteMany({ where: { id: flatA.id } });
    await prisma.society.deleteMany({
      where: { id: { in: [societyA.id, societyB.id] } },
    });
    await prisma.$disconnect();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
