/**
 * Creates one local super admin. The caller must set DATABASE_URL before
 * Node starts. This file refuses every database except the local v2 database.
 * It does not read .env for the database and does not change incentive switches.
 */
const { PrismaClient } = require("@prisma/client");

const REQUIRED_HOST = "127.0.0.1";
const REQUIRED_PORT = "5432";
const REQUIRED_DATABASE = "societybites_incentive_integration_v2";
const PHONE = "+919000000000";

function assertSafeUrl(value) {
  if (!value || typeof value !== "string") throw new Error("DATABASE_URL must be set by the local prompt");
  const lowered = value.toLowerCase();
  if (lowered.includes("supabase") || lowered.includes("pooler")) throw new Error("Refusing a Supabase connection");
  const parsed = new URL(value);
  const database = decodeURIComponent(parsed.pathname.replace(/^\//, ""));
  if (parsed.hostname !== REQUIRED_HOST || parsed.port !== REQUIRED_PORT || database !== REQUIRED_DATABASE) {
    throw new Error("Refusing a database other than 127.0.0.1:5432/societybites_incentive_integration_v2");
  }
  if ([...parsed.searchParams.keys()].some((key) => key !== "connection_limit")) {
    throw new Error("Refusing a database URL with unexpected parameters");
  }
}

async function main() {
  assertSafeUrl(process.env.DATABASE_URL);
  const prisma = new PrismaClient({ datasources: { db: { url: process.env.DATABASE_URL } } });
  try {
    const identity = await prisma.$queryRaw`
      SELECT current_database() AS db,
             host(inet_server_addr()) AS host,
             inet_server_port()::int AS port
    `;
    const row = identity[0];
    if (row.db !== REQUIRED_DATABASE || String(row.host) !== REQUIRED_HOST || Number(row.port) !== Number(REQUIRED_PORT)) {
      throw new Error("ABORT_IDENTITY");
    }
    const existing = await prisma.user.findUnique({ where: { phone: PHONE } });
    if (existing) {
      await prisma.user.update({
        where: { id: existing.id },
        data: { role: "super_admin", suspended: false, name: existing.name || "Local super admin" },
      });
      console.log(`UPDATED phone=${PHONE} role=super_admin db=${row.db}`);
    } else {
      await prisma.user.create({
        data: { phone: PHONE, name: "Local super admin", role: "super_admin", suspended: false },
      });
      console.log(`CREATED phone=${PHONE} role=super_admin db=${row.db}`);
    }
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  const message = String(error && error.message ? error.message : error);
  console.error(message.replace(/postgresql:\/\/\S+/gi, "postgresql://[redacted]"));
  process.exit(1);
});
