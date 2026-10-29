/**
 * Sequential test runner that kills hung suites (Express listeners / Prisma).
 * Usage:
 *   node scripts/run-tests.js --unit
 *   node scripts/run-tests.js --regression
 *   node scripts/run-tests.js tests/foo.test.js
 */
const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const testsDir = path.join(root, "tests");
const timeoutMs = Number(process.env.TEST_TIMEOUT_MS || 120000);

/** Fast / no-server (or tiny) checks. Keep this list quick for local loops. */
const UNIT = [
  "order-number",
  "admin-order-detail",
  "prisma-pool",
  "kitchen-hours",
  "food-type",
  "geo-distance",
  "buyer-contact",
  "listing-discount",
  "listing-categories",
  "listing-image-optimize",
  "test-listing-names",
  "notifications-payload",
  "marketing-push",
];

/**
 * Curated end-to-end API journeys (DB + Express). Broader than unit, narrower
 * than full `npm test`. Prefer critical money/auth/society paths here.
 */
const REGRESSION = [
  "notifications-payload",
  "regression-order-journeys",
  "preorder-deep-link-auth",
  "order-lifecycle",
  "order-cancellation",
  "order-idempotency",
  "buyer-order-visibility",
  "seller-order-history",
  "society-scoping",
  "cross-society-order",
  "preorder",
  "listing-catalog",
  "test-otp",
  "app-force-update",
];

function suitePath(name) {
  if (name.endsWith(".js")) {
    return path.isAbsolute(name) ? name : path.join(root, name);
  }
  return path.join(testsDir, `${name}.test.js`);
}

function parseArgs(argv) {
  const names = [];
  let mode = null;
  for (const arg of argv) {
    if (arg === "--unit") mode = "unit";
    else if (arg === "--regression") mode = "regression";
    else if (arg === "--all") mode = "all";
    else names.push(arg);
  }
  if (names.length) return names;
  if (mode === "unit") return UNIT;
  if (mode === "regression") return REGRESSION;
  if (mode === "all") {
    return fs
      .readdirSync(testsDir)
      .filter((file) => file.endsWith(".test.js"))
      .map((file) => file.replace(/\.test\.js$/, ""));
  }
  return REGRESSION;
}

function looksFailed(code, output) {
  if (code !== 0 && code !== null) return true;
  return /^\s*(Error|AssertionError|\w*Error):/m.test(output);
}

function runSuite(name) {
  const file = suitePath(name);
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [file], {
      cwd: root,
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    child.stdout.on("data", (chunk) => {
      const text = chunk.toString();
      output += text;
      process.stdout.write(text);
    });
    child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      output += text;
      process.stderr.write(text);
    });
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
    }, timeoutMs);
    child.on("exit", (code) => {
      clearTimeout(timer);
      resolve({ name, failed: looksFailed(code, output) });
    });
  });
}

async function main() {
  const suites = parseArgs(process.argv.slice(2));
  const failed = [];
  for (const name of suites) {
    const file = suitePath(name);
    if (!fs.existsSync(file)) {
      console.error(`Missing ${file}`);
      failed.push(name);
      continue;
    }
    console.log(`\n=== ${name} ===`);
    const result = await runSuite(name);
    if (result.failed) {
      console.error(`FAIL  ${name}`);
      failed.push(name);
    } else {
      console.log(`PASS  ${name}`);
    }
  }
  if (failed.length) {
    console.error(`\nFailed: ${failed.join(", ")}`);
    process.exit(1);
  }
  console.log("\nAll suites passed.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
