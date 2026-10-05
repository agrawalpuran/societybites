require("dotenv").config();

const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const { assertIssueCreate, issueReference, sortIssues } = require("../lib/issueReports");
const issueRoutes = require("../routes/issues");
const adminRoutes = require("../routes/admin");
const orderRoutes = require("../routes/orders");

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

function expectCreateError(body, user, snippet) {
  try {
    assertIssueCreate(body, user);
    throw new Error("expected an error");
  } catch (err) {
    if (err.message === "expected an error") throw err;
    assert(err.statusCode === 400, `status ${err.statusCode}`);
    assert(String(err.message).includes(snippet), err.message);
  }
}

async function main() {
  assert(issueReference(1024) === "SE-1024", "reference format");
  expectCreateError({ category: "OTHER", description: "   " }, { id: "u", role: "buyer" }, "happened");
  expectCreateError({ category: "NOPE", description: "Hello" }, { id: "u", role: "buyer" }, "category");
  const trusted = assertIssueCreate(
    {
      category: "PAYMENT_UPI",
      description: "  Payment failed  ",
      userId: "someone-else",
      role: "super_admin",
      orderId: "order-1",
      listingId: "listing-1",
      platform: "android",
    },
    { id: "real-user", role: "buyer" }
  );
  assert(trusted.userId === "real-user", "client userId is ignored");
  assert(trusted.userRole === "buyer", "client role is ignored");
  assert(trusted.description === "Payment failed", "description is trimmed");
  assert(trusted.orderId === "order-1" && trusted.listingId === "listing-1", "context kept");
  const ranked = sortIssues([
    { status: "CLOSED", createdAt: "2026-10-05T00:00:00Z" },
    { status: "OPEN", createdAt: "2026-10-01T00:00:00Z" },
    { status: "UNDER_REVIEW", createdAt: "2026-10-04T00:00:00Z" },
  ]);
  assert(ranked[0].status === "OPEN" && ranked[1].status === "UNDER_REVIEW", "open issues sort first");

  const app = express();
  app.use(express.json());
  app.use("/issues", issueRoutes);
  app.use("/admin", adminRoutes);
  app.use("/orders", orderRoutes);
  app.use((err, _req, res, _next) => {
    res.status(err.statusCode || 500).json({ error: err.statusCode ? err.message : "Internal server error" });
  });
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  const stamp = String(Date.now()).slice(-8);
  const buyer = await prisma.user.create({
    data: { phone: `+9188${stamp}01`, name: "Issue Buyer", role: "buyer" },
  });
  const seller = await prisma.user.create({
    data: { phone: `+9188${stamp}02`, name: "Issue Seller", role: "seller" },
  });
  const admin = await prisma.user.create({
    data: { phone: `+9188${stamp}03`, name: "Issue Admin", role: "super_admin" },
  });
  const buyerToken = signToken(buyer);
  const sellerToken = signToken(seller);
  const adminToken = signToken(admin);

  try {
    const unauth = await jsonRequest(server, {
      method: "POST",
      path: "/issues",
      body: { category: "OTHER", description: "Hello" },
    });
    assert(unauth.status === 401, "issues stay behind the existing session check");
    const ordersUnauth = await jsonRequest(server, { method: "GET", path: "/orders" });
    assert(ordersUnauth.status === 401, "order routes still require authentication");

    const created = await jsonRequest(server, {
      method: "POST",
      path: "/issues",
      token: buyerToken,
      body: {
        category: "PAYMENT_UPI",
        description: "Payment failed after scanning QR",
        userId: seller.id,
        role: "super_admin",
        orderId: "SB-548969",
        listingId: "listing-88",
        sellerId: seller.id,
        platform: "ANDROID",
      },
    });
    assert(created.status === 201, `buyer create ${created.status} ${JSON.stringify(created.json)}`);
    assert(created.json.status === "OPEN", "default status is OPEN");
    assert(/^SE-\d+$/.test(created.json.reference), "reference is generated");
    assert(created.json.userId === buyer.id, "issue belongs to the signed-in buyer");
    assert(created.json.userRole === "buyer", "buyer role is stored");
    assert(created.json.orderId === "SB-548969", "order context is preserved");
    assert(created.json.listingId === "listing-88", "listing context is preserved");
    assert(created.json.sellerId === seller.id, "seller context is preserved");

    const sellerIssue = await jsonRequest(server, {
      method: "POST",
      path: "/issues",
      token: sellerToken,
      body: { category: "BUYER", description: "Buyer did not collect the order" },
    });
    assert(sellerIssue.status === 201, "seller can create an issue");
    assert(sellerIssue.json.userRole === "seller", "seller role is stored");
    assert(sellerIssue.json.status === "OPEN", "seller issue starts open");

    const mine = await jsonRequest(server, { method: "GET", path: "/issues/my", token: buyerToken });
    assert(mine.status === 200, "buyer can list own issues");
    assert(mine.json.issues.length === 1, "buyer sees only their issue");
    assert(mine.json.issues[0].id === created.json.id, "own issue is returned");

    const ownDetail = await jsonRequest(server, {
      method: "GET",
      path: `/issues/${created.json.id}`,
      token: buyerToken,
    });
    assert(ownDetail.status === 200, "buyer can open own issue");

    const stolen = await jsonRequest(server, {
      method: "GET",
      path: `/issues/${created.json.id}`,
      token: sellerToken,
    });
    assert(stolen.status === 404, "another user cannot open the issue");
    const stolenList = await jsonRequest(server, { method: "GET", path: "/issues/my", token: sellerToken });
    assert(
      stolenList.json.issues.every((row) => row.userId === seller.id),
      "my reports never include another user"
    );

    const buyerAdmin = await jsonRequest(server, {
      method: "GET",
      path: "/admin/issues",
      token: buyerToken,
    });
    assert(buyerAdmin.status === 403, "buyers cannot list every issue");

    const all = await jsonRequest(server, { method: "GET", path: "/admin/issues", token: adminToken });
    assert(all.status === 200, "admin can list issues");
    assert(all.json.issues.length >= 2, "admin sees more than one user's issues");
    assert(all.json.issues[0].status === "OPEN", "unresolved issues stay at the top");

    const openOnly = await jsonRequest(server, {
      method: "GET",
      path: "/admin/issues?status=OPEN",
      token: adminToken,
    });
    assert(openOnly.json.issues.every((row) => row.status === "OPEN"), "status filter works");

    const reviewed = await jsonRequest(server, {
      method: "PATCH",
      path: `/admin/issues/${created.json.id}`,
      token: adminToken,
      body: { status: "UNDER_REVIEW", adminResponse: "We are checking this issue." },
    });
    assert(reviewed.status === 200, "admin can change status");
    assert(reviewed.json.status === "UNDER_REVIEW", "status updates");
    assert(reviewed.json.adminResponse === "We are checking this issue.", "admin response is saved");

    const updated = await jsonRequest(server, {
      method: "PATCH",
      path: `/admin/issues/${created.json.id}`,
      token: adminToken,
      body: { adminResponse: "Payment has been confirmed." },
    });
    assert(updated.json.adminResponse === "Payment has been confirmed.", "admin response can be updated");
    assert(updated.json.status === "UNDER_REVIEW", "response update keeps status");

    const after = await jsonRequest(server, {
      method: "GET",
      path: `/issues/${created.json.id}`,
      token: buyerToken,
    });
    assert(after.json.adminResponse === "Payment has been confirmed.", "owner sees the latest response");

    const blocked = await jsonRequest(server, {
      method: "PATCH",
      path: `/admin/issues/${created.json.id}`,
      token: buyerToken,
      body: { status: "CLOSED" },
    });
    assert(blocked.status === 403, "buyers cannot change status");

    console.log("issue reports ok");
  } finally {
    await prisma.issueReport.deleteMany({
      where: { userId: { in: [buyer.id, seller.id, admin.id] } },
    });
    await prisma.user.deleteMany({ where: { id: { in: [buyer.id, seller.id, admin.id] } } });
    server.close();
    await prisma.$disconnect();
  }
}

main().catch(async (err) => {
  console.error(err);
  try {
    await prisma.$disconnect();
  } catch (_) {}
  process.exit(1);
});
