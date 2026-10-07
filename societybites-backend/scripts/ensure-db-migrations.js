/**
 * Applies pending Prisma migrations before the API starts (Render / production).
 * Skipped when SKIP_DB_MIGRATE=true (e.g. local dev using `npm run dev` only).
 * Requires DIRECT_URL for Supabase direct/session pooler (see .env.example).
 */
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

if (process.env.SKIP_DB_MIGRATE === "true") {
  process.exit(0);
}

const backendRoot = path.join(__dirname, "..");
const prismaCli = path.join(backendRoot, "node_modules", "prisma", "build", "index.js");
if (!fs.existsSync(prismaCli)) {
  console.error("[ensure-db-migrations] Prisma CLI not found. Run npm install in societybites-backend.");
  process.exit(1);
}

const result = spawnSync(process.execPath, [prismaCli, "migrate", "deploy"], {
  cwd: backendRoot,
  stdio: "inherit",
  env: process.env,
});

if (result.error) {
  console.error("[ensure-db-migrations]", result.error.message);
  process.exit(1);
}
if (result.status !== 0) {
  console.error("[ensure-db-migrations] prisma migrate deploy failed");
  process.exit(result.status || 1);
}
