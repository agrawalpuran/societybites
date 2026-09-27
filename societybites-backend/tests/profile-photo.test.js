const {
  parseImageUpload,
  normalizeStoredProfilePhotoUrl,
  storagePrefixForPurpose,
  TOO_LARGE_MESSAGE,
  UNSUPPORTED_MESSAGE,
} = require("../lib/profileImage");
const { serializeListing } = require("../utils/listingSerializer");
const { serializeCampaign } = require("../lib/preorder");
const { MAX_BYTES } = require("../lib/objectStorage");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function jpegBytes() {
  return Buffer.from([0xff, 0xd8, 0xff, 0xd9, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b]);
}

function main() {
  const parsed = parseImageUpload({
    imageBase64: jpegBytes().toString("base64"),
    mimeType: "image/jpeg",
  });
  assert(parsed.mimeType === "image/jpeg", "jpeg mime is accepted");
  assert(parsed.buffer.length > 0, "decoded buffer");

  try {
    parseImageUpload({ imageBase64: Buffer.from("not-an-image").toString("base64"), mimeType: "image/jpeg" });
    throw new Error("text should fail");
  } catch (err) {
    if (err.message === "text should fail") throw err;
    assert(err.statusCode === 400, "unsupported data is 400");
    assert(err.message === UNSUPPORTED_MESSAGE, "unsupported message");
  }

  try {
    parseImageUpload({
      imageBase64: jpegBytes().toString("base64"),
      mimeType: "application/pdf",
    });
    throw new Error("pdf should fail");
  } catch (err) {
    if (err.message === "pdf should fail") throw err;
    assert(err.message === UNSUPPORTED_MESSAGE, "pdf rejected");
  }

  const huge = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(MAX_BYTES + 10, 1)]);
  try {
    parseImageUpload({ imageBase64: huge.toString("base64"), mimeType: "image/jpeg" });
    throw new Error("huge should fail");
  } catch (err) {
    if (err.message === "huge should fail") throw err;
    assert(err.message === TOO_LARGE_MESSAGE, "oversize rejected with UX copy");
  }

  assert(storagePrefixForPurpose("profile") === "profiles", "profile prefix");
  assert(storagePrefixForPurpose("listing") === "listings", "listing prefix");

  assert(normalizeStoredProfilePhotoUrl(null) === null, "null clears photo");
  assert(normalizeStoredProfilePhotoUrl("") === null, "empty clears photo");
  assert(
    normalizeStoredProfilePhotoUrl("https://cdn.example/profiles/a.jpg") ===
      "https://cdn.example/profiles/a.jpg",
    "https url accepted"
  );
  try {
    normalizeStoredProfilePhotoUrl("javascript:alert(1)");
    throw new Error("js url should fail");
  } catch (err) {
    if (err.message === "js url should fail") throw err;
    assert(err.statusCode === 400, "javascript url rejected");
  }

  const serialized = serializeListing({
    id: "l1",
    name: "Idli",
    price: 40,
    quantity: 1,
    sellerId: "seller-a",
    seller: { name: "Anita", profilePhotoUrl: "https://cdn.example/a.jpg", upiId: null },
    reviews: [],
  });
  assert(serialized.sellerProfilePhotoUrl === "https://cdn.example/a.jpg", "listing carries one photo url");
  assert(serialized.sellerName === "Anita", "existing listing fields still serialize");

  const withoutPhoto = serializeListing({
    id: "l2",
    name: "Dosa",
    price: 50,
    quantity: 1,
    sellerId: "seller-b",
    seller: { name: "Puran" },
    reviews: [],
  });
  assert(withoutPhoto.sellerProfilePhotoUrl === null, "missing photo stays null");

  const campaign = serializeCampaign({
    id: "c1",
    sellerId: "seller-a",
    societyId: "s1",
    title: "Weekend",
    status: "open",
    orderOpenAt: new Date(),
    orderCutoffAt: new Date(),
    fulfilmentAt: new Date(),
    seller: { profilePhotoUrl: "https://cdn.example/a.jpg", sellingReachLevel: "MY_SOCIETY" },
  });
  assert(campaign.sellerProfilePhotoUrl === "https://cdn.example/a.jpg", "campaign carries seller photo");

  console.log("profile-photo unit tests passed");
}

async function httpTests() {
  require("dotenv").config();
  const http = require("http");
  const express = require("express");
  const prisma = require("../lib/prisma");
  const { signToken } = require("../lib/jwt");
  const authRoutes = require("../routes/auth");

  const PHONE_A = "+919800000181";
  const PHONE_B = "+919800000182";

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

  const app = express();
  app.use(express.json({ limit: "8mb" }));
  app.use("/auth", authRoutes);
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
    const sellerA = await prisma.user.upsert({
      where: { phone: PHONE_A },
      update: { role: "seller", profilePhotoUrl: "https://cdn.example/a.jpg" },
      create: {
        phone: PHONE_A,
        name: "Photo A",
        role: "seller",
        profilePhotoUrl: "https://cdn.example/a.jpg",
      },
    });
    const sellerB = await prisma.user.upsert({
      where: { phone: PHONE_B },
      update: { role: "seller", profilePhotoUrl: "https://cdn.example/b.jpg" },
      create: {
        phone: PHONE_B,
        name: "Photo B",
        role: "seller",
        profilePhotoUrl: "https://cdn.example/b.jpg",
      },
    });
    const tokenA = signToken(sellerA);

    const junk = await jsonRequest(server, {
      method: "POST",
      path: "/auth/me/profile-photo",
      token: tokenA,
      body: { imageBase64: Buffer.from("not-an-image").toString("base64"), mimeType: "image/jpeg" },
    });
    assert(junk.status === 400, "unsupported upload is 400");

    const stolen = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: tokenA,
      body: {
        userId: sellerB.id,
        profilePhotoUrl: "https://cdn.example/hacked.jpg",
      },
    });
    assert(stolen.status === 200, "own profile patch succeeds");
    assert(stolen.json.user.id === sellerA.id, "token user is updated, not body userId");
    assert(
      stolen.json.user.profilePhotoUrl === "https://cdn.example/hacked.jpg",
      "seller A photo changed"
    );

    const stillB = await prisma.user.findUnique({ where: { id: sellerB.id } });
    assert(stillB.profilePhotoUrl === "https://cdn.example/b.jpg", "seller B photo unchanged");

    const cleared = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: tokenA,
      body: { profilePhotoUrl: null },
    });
    assert(cleared.status === 200, "clear photo");
    assert(cleared.json.user.profilePhotoUrl == null, "photo removed");
  } finally {
    server.close();
  }
}

main();
httpTests()
  .then(() => console.log("profile-photo tests passed"))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
