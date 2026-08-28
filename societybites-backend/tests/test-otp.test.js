process.env.TEST_OTP_ENABLED = "true";
process.env.TEST_PHONE_NUMBERS =
  "1111111111,2222222222,3333333333,4444444444,5555555555,6666666666,7777777777,8888888888,9999999999";
process.env.TEST_OTP = "123456";
process.env.OTP_IP_MAX = "200";

require("dotenv").config();

const http = require("http");
const express = require("express");
const jwt = require("jsonwebtoken");
const prisma = require("../lib/prisma");
const { JWT_SECRET } = require("../lib/jwt");
const twoFactor = require("../lib/twoFactor");
const testOtp = require("../lib/testOtp");
const authRoutes = require("../routes/auth");

const TEST_NUMBERS = process.env.TEST_PHONE_NUMBERS.split(",");
const NON_TEST_PHONE = "6000000001";
const TEST_PHONES_E164 = TEST_NUMBERS.map((n) => `+91${n}`);
const CLEANUP_PHONES = [...TEST_PHONES_E164, `+91${NON_TEST_PHONE}`];

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function jsonRequest(server, { method, path, body }) {
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
          resolve({ status: res.statusCode, json, raw: data });
        });
      }
    );
    req.on("error", reject);
    if (payload) req.write(payload);
    req.end();
  });
}

function assertNoSecretsLeaked(raw) {
  const text = String(raw || "");
  assert(!/"TEST_OTP"/i.test(text), "response must not mention TEST_OTP");
  assert(
    !/"TEST_PHONE_NUMBERS"/i.test(text),
    "response must not mention TEST_PHONE_NUMBERS"
  );
  assert(!/"testOtp"/i.test(text), "response must not mention testOtp");
}

async function sendOtp(server, phone) {
  return jsonRequest(server, {
    method: "POST",
    path: "/auth/send-otp",
    body: { phone },
  });
}

async function verifyOtp(server, phone, otp) {
  return jsonRequest(server, {
    method: "POST",
    path: "/auth/verify-otp",
    body: { phone, otp },
  });
}

async function cleanupUsersCreatedDuringTest(preexistingPhones) {
  const created = await prisma.user.findMany({
    where: {
      phone: { in: CLEANUP_PHONES.filter((p) => !preexistingPhones.has(p)) },
    },
    select: { id: true },
  });
  const ids = created.map((u) => u.id);
  if (!ids.length) return;
  await prisma.refreshToken.deleteMany({ where: { userId: { in: ids } } });
  await prisma.deviceToken.deleteMany({ where: { userId: { in: ids } } });
  await prisma.user.deleteMany({ where: { id: { in: ids } } });
}

async function main() {
  const origSend = twoFactor.sendOtp;
  const origVerify = twoFactor.verifyOtp;
  const sendCalls = [];
  const verifyCalls = [];

  twoFactor.sendOtp = async (phone) => {
    sendCalls.push(phone);
    return { sessionId: "mock-2factor-session" };
  };
  twoFactor.verifyOtp = async (sessionId, otp) => {
    verifyCalls.push({ sessionId, otp });
    return { matched: true };
  };

  const app = express();
  app.use(express.json());
  app.use("/auth", authRoutes);
  app.use((err, _req, res, _next) => {
    const statusCode = err.statusCode || 500;
    res.status(statusCode).json({
      error: statusCode === 500 ? "Internal server error" : err.message,
    });
  });

  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  let preexistingPhones = new Set();
  try {
    const preexisting = await prisma.user.findMany({
      where: { phone: { in: CLEANUP_PHONES } },
    });
    const preexistingByPhone = Object.fromEntries(
      preexisting.map((u) => [u.phone, u])
    );
    preexistingPhones = new Set(preexisting.map((u) => u.phone));

    assert(testOtp.isEnabled(), "TEST_OTP_ENABLED=true must enable bypass");
    for (const number of TEST_NUMBERS) {
      assert(testOtp.isTestPhone(number), `${number} must be a test phone`);
      assert(testOtp.otpMatches("123456"), "123456 must match TEST_OTP");
    }
    assert(!testOtp.isTestPhone(NON_TEST_PHONE), "non-test number must not bypass");
    assert(!testOtp.otpMatches("000000"), "wrong OTP must not match");

    const sessionByPhone = {};
    for (const number of TEST_NUMBERS) {
      const sent = await sendOtp(server, number);
      assert(sent.status === 200 && sent.json?.ok === true, `send-otp failed for ${number}`);
      assertNoSecretsLeaked(sent.raw);

      const verified = await verifyOtp(server, number, "123456");
      assert(
        verified.status === 200 && verified.json?.success === true,
        `verify-otp 123456 failed for ${number}: ${verified.raw}`
      );
      assertNoSecretsLeaked(verified.raw);
      assert(verified.json.token, `missing access token for ${number}`);
      assert(verified.json.refreshToken, `missing refresh token for ${number}`);
      assert(verified.json.user?.phone === `+91${number}`, `user.phone mismatch for ${number}`);
      assert(verified.json.user?.id, `missing user id for ${number}`);
      const prior = preexistingByPhone[`+91${number}`];
      if (prior) {
        assert(verified.json.user.id === prior.id, `must restore existing user for ${number}`);
        assert(
          verified.json.user.societyId === prior.societyId,
          `must keep existing society for ${number}`
        );
      } else {
        assert(
          verified.json.user.societyId == null,
          `new test user ${number} must not have a society`
        );
        assert(
          verified.json.user.flatId == null,
          `new test user ${number} must not have a flat`
        );
      }

      const payload = jwt.verify(verified.json.token, JWT_SECRET);
      assert(payload.userId === verified.json.user.id, "token userId must match session user");
      assert(payload.phone === `+91${number}`, "token phone must match");

      sessionByPhone[number] = verified.json;
    }

    assert(
      sendCalls.length === 0,
      `test numbers must not call 2Factor sendOtp, got ${sendCalls.length}`
    );
    assert(
      verifyCalls.length === 0,
      `test numbers must not call 2Factor verifyOtp, got ${verifyCalls.length}`
    );

    const wrongSend = await sendOtp(server, "1111111111");
    assert(wrongSend.status === 200, "resend after success should work (challenge was consumed)");
    const wrong = await verifyOtp(server, "1111111111", "000000");
    assert(wrong.status === 401 && wrong.json?.error === "Invalid OTP", "wrong OTP must fail");
    assertNoSecretsLeaked(wrong.raw);
    assert(verifyCalls.length === 0, "wrong OTP on test number must not call 2Factor");

    const nonTestSend = await sendOtp(server, NON_TEST_PHONE);
    assert(nonTestSend.status === 200 && nonTestSend.json?.ok === true, "non-test send-otp failed");
    assert(
      sendCalls.length === 1 && sendCalls[0] === `91${NON_TEST_PHONE}`,
      `non-test number must call 2Factor sendOtp, got ${JSON.stringify(sendCalls)}`
    );

    const nonTestVerify = await verifyOtp(server, NON_TEST_PHONE, "111111");
    assert(nonTestVerify.status === 200 && nonTestVerify.json?.success === true, "mocked 2Factor verify failed");
    assert(verifyCalls.length === 1, "non-test number must call 2Factor verifyOtp");
    assert(verifyCalls[0].sessionId === "mock-2factor-session", "2Factor session id mismatch");
    assert(verifyCalls[0].otp === "111111", "2Factor must receive the entered OTP");

    const incompleteNumber = TEST_NUMBERS.find(
      (n) => sessionByPhone[n].user.societyId == null
    );
    assert(
      incompleteNumber,
      "at least one test number must be an incomplete user (no society) so onboarding can continue"
    );
    const existingId = sessionByPhone[incompleteNumber].user.id;
    const againSend = await sendOtp(server, incompleteNumber);
    assert(againSend.status === 200, "existing user send-otp failed");
    const again = await verifyOtp(server, incompleteNumber, "123456");
    assert(
      again.status === 200 && again.json?.user?.id === existingId,
      "existing user must restore same session user"
    );
    assert(
      again.json.user.societyId == null,
      "incomplete user must still have no society (onboarding)"
    );
    assert(
      again.json.user.flatId == null,
      "incomplete user must still have no flat (onboarding)"
    );
    assert(sendCalls.length === 1, "repeat test-number login must not call 2Factor");

    process.env.TEST_OTP_ENABLED = "false";
    assert(!testOtp.isEnabled(), "missing/false TEST_OTP_ENABLED must disable bypass");
    assert(!testOtp.isTestPhone("1111111111"), "bypass must be off when disabled");
    const disabled = await sendOtp(server, "1111111111");
    assert(
      disabled.status === 400,
      "when bypass is off, non-Indian test numbers must be rejected"
    );
    process.env.TEST_OTP_ENABLED = "true";

    console.log("test-otp tests passed");
  } finally {
    twoFactor.sendOtp = origSend;
    twoFactor.verifyOtp = origVerify;
    process.env.TEST_OTP_ENABLED = "true";
    await cleanupUsersCreatedDuringTest(preexistingPhones);
    await new Promise((resolve) => server.close(resolve));
    await prisma.$disconnect();
  }
  process.exit(0);
}

main().catch(async (err) => {
  console.error(err);
  await prisma.$disconnect();
  process.exit(1);
});
