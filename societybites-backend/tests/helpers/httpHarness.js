const http = require("http");
const express = require("express");
const { signToken } = require("../../lib/jwt");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function jsonRequest(server, { method, path, token, body }) {
  const address = server.address();
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : Buffer.from(JSON.stringify(body));
    const request = http.request(
      {
        hostname: "127.0.0.1",
        port: address.port,
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
      (response) => {
        let data = "";
        response.on("data", (chunk) => (data += chunk));
        response.on("end", () => {
          let json = null;
          try {
            json = data ? JSON.parse(data) : null;
          } catch (_) {}
          resolve({ status: response.statusCode, json });
        });
      }
    );
    request.on("error", reject);
    if (payload) request.write(payload);
    request.end();
  });
}

function orderApp() {
  const orderRoutes = require("../../routes/orders");
  const paymentRoutes = require("../../routes/payments");
  const app = express();
  app.use(express.json());
  app.use("/orders", orderRoutes);
  app.use("/payments", paymentRoutes);
  app.use((error, _req, res, _next) => {
    const statusCode = error.statusCode || 500;
    res
      .status(statusCode)
      .json({ error: statusCode === 500 ? "Internal server error" : error.message });
  });
  return app;
}

function listen(app) {
  return new Promise((resolve) => {
    const listener = app.listen(0, "127.0.0.1", () => resolve(listener));
  });
}

function closeServer(server) {
  return new Promise((resolve) => server.close(() => resolve()));
}

async function createOrder(server, { token, listingId, paymentMethod }) {
  const created = await jsonRequest(server, {
    method: "POST",
    path: "/orders",
    token,
    body: {
      paymentMethod,
      items: [{ listingId, quantity: 1 }],
    },
  });
  assert(
    created.status === 201,
    `order create failed: ${created.status} ${JSON.stringify(created.json)}`
  );
  return created.json;
}

function patchStatus(server, { token, orderId, status, reason }) {
  return jsonRequest(server, {
    method: "PATCH",
    path: `/orders/${orderId}/status`,
    token,
    body: {
      status,
      ...(status === "cancelled" ? { reason: reason || "Changed my mind" } : {}),
    },
  });
}

module.exports = {
  assert,
  jsonRequest,
  orderApp,
  listen,
  closeServer,
  createOrder,
  patchStatus,
  signToken,
};
