/**
 * Read-only identity and schema check for the isolated incentive database.
 * The runner must set DATABASE_URL before Node starts. This file checks that
 * URL before opening a client, so .env is never consulted. It only runs SELECT.
 */
const { PrismaClient } = require("@prisma/client");

const REQUIRED_HOST = "127.0.0.1";
const REQUIRED_PORT = "5432";
const REQUIRED_DATABASE = "societybites_incentive_integration_v2";
const EXPECTED_MIGRATIONS = [
  "20261117120000_incentive_engine_foundation",
  "20261117183000_incentive_event_processing",
  "20261117203000_incentive_referral_code_pin",
  "20261117213000_incentive_referral_attribution",
  "20261117223000_listing_first_published_at",
];
const EXPECTED_TRIGGERS = [
  "incentive_ledger_no_update",
  "incentive_ledger_no_delete",
  "incentive_ledger_guard_insert",
];

function assertSafeUrl(value) {
  if (!value || typeof value !== "string") {
    throw new Error("DATABASE_URL must be set by the local v2 runner");
  }
  const lowered = value.toLowerCase();
  if (lowered.includes("supabase") || lowered.includes("pooler")) {
    throw new Error("Refusing a Supabase connection");
  }
  let parsed;
  try {
    parsed = new URL(value);
  } catch (error) {
    throw new Error("DATABASE_URL is not a valid URL");
  }
  const database = decodeURIComponent(parsed.pathname.replace(/^\//, ""));
  if (parsed.hostname !== REQUIRED_HOST) throw new Error(`host must be ${REQUIRED_HOST}`);
  if (parsed.port !== REQUIRED_PORT) throw new Error(`port must be ${REQUIRED_PORT}`);
  if (database !== REQUIRED_DATABASE) throw new Error(`database must be ${REQUIRED_DATABASE}`);
  for (const key of parsed.searchParams.keys()) {
    if (key !== "connection_limit") throw new Error("DATABASE_URL has an unexpected parameter");
  }
}

function enabledValue(value) {
  return typeof value === "string"
    && value.replace(/^[ \t\n\r\f\v]+/, "").replace(/[ \t\n\r\f\v]+$/, "") === "true";
}

function log(line) {
  process.stdout.write(`${line}\n`);
}

async function main() {
  assertSafeUrl(process.env.DATABASE_URL);
  const identityOnly = process.argv.includes("--identity-only");
  let prisma;
  try {
    prisma = new PrismaClient({ datasources: { db: { url: process.env.DATABASE_URL } } });
    const identity = await prisma.$queryRaw`
      SELECT current_database() AS db,
             host(inet_server_addr()) AS host,
             inet_server_port()::int AS port
    `;
    const row = identity[0];
    log(`IDENTITY db=${row.db} host=${row.host} port=${row.port}`);
    if (row.db !== REQUIRED_DATABASE || String(row.host) !== REQUIRED_HOST || Number(row.port) !== Number(REQUIRED_PORT)) {
      throw new Error("ABORT_IDENTITY");
    }
    if (identityOnly) {
      log("IDENTITY_ONLY_OK");
      return;
    }
    try {
      const tables = await prisma.$queryRaw`
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'public'
        ORDER BY table_name
      `;
      log(`PUBLIC_TABLES ${tables.map((item) => item.table_name).join(",") || "none"}`);
    } catch (error) {
      log("PUBLIC_TABLES unreadable");
    }
    let migrations = null;
    try {
      migrations = await prisma.$queryRaw`
        SELECT migration_name,
               (finished_at IS NOT NULL) AS finished,
               (rolled_back_at IS NOT NULL) AS rolled_back
        FROM "_prisma_migrations"
        ORDER BY migration_name
      `;
    } catch (error) {
      log("MIGRATION_TABLE absent");
    }
    if (migrations) {
      const names = migrations.map((item) => item.migration_name);
      const duplicate = names.find((name, index) => names.indexOf(name) !== index);
      log(`MIGRATION_ROWS ${migrations.length}`);
      log(`MIGRATION_DUPLICATES ${duplicate || "none"}`);
      const unfinished = migrations.filter((item) => !item.finished || item.rolled_back).map((item) => item.migration_name);
      log(`MIGRATION_UNFINISHED ${unfinished.length ? unfinished.join(",") : "none"}`);
      for (const name of EXPECTED_MIGRATIONS) {
        const match = migrations.find((item) => item.migration_name === name);
        const state = match && match.finished && !match.rolled_back ? "applied" : "absent";
        log(`MIGRATION ${name} ${state}`);
      }
      log(`LEDGER_GUARD_IN_PRISMA_HISTORY ${names.some((name) => String(name).includes("ledger_guard")) ? "yes" : "no"}`);
    } else {
      for (const name of EXPECTED_MIGRATIONS) log(`MIGRATION ${name} absent`);
      log("LEDGER_GUARD_IN_PRISMA_HISTORY no");
    }
    let triggers = null;
    try {
      triggers = await prisma.$queryRaw`
        SELECT tgname::text AS name, tgenabled::text AS enabled
        FROM pg_trigger
        WHERE tgrelid = '"IncentiveLedgerEntry"'::regclass AND NOT tgisinternal
        ORDER BY tgname
      `;
    } catch (error) {
      log("LEDGER_TRIGGER_TABLE absent");
    }
    if (triggers) {
      log(`LEDGER_TRIGGERS ${triggers.map((item) => `${item.name}:${item.enabled}`).join(",") || "none"}`);
      const missingTrigger = EXPECTED_TRIGGERS.filter((name) => !triggers.some((item) => item.name === name && item.enabled === "O"));
      log(`LEDGER_TRIGGERS_MISSING ${missingTrigger.length ? missingTrigger.join(",") : "none"}`);
    } else {
      log(`LEDGER_TRIGGERS_MISSING ${EXPECTED_TRIGGERS.join(",")}`);
    }
    try {
      const column = await prisma.$queryRaw`
        SELECT is_nullable
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'Listing' AND column_name = 'firstPublishedAt'
      `;
      log(`LISTING_FIRST_PUBLISHED ${column.length ? column[0].is_nullable : "absent"}`);
    } catch (error) {
      log("LISTING_FIRST_PUBLISHED unreadable");
    }
    let enabled = false;
    try {
      const flags = await prisma.$queryRaw`SELECT key, value FROM "IncentiveSetting" ORDER BY key`;
      if (!flags.length) log("FLAGS none");
      for (const flag of flags) {
        const on = enabledValue(flag.value);
        if (on) enabled = true;
        log(`FLAG ${flag.key} enabled=${on}`);
      }
    } catch (error) {
      log("FLAGS unreadable");
    }
    log(`FLAGS_ENABLED ${enabled ? "yes" : "no"}`);
    try {
      const campaigns = await prisma.$queryRaw`
        SELECT status, COUNT(*)::int AS count
        FROM "IncentiveCampaign"
        GROUP BY status
        ORDER BY status
      `;
      log(`CAMPAIGNS ${campaigns.length ? campaigns.map((item) => `${item.status}:${item.count}`).join(",") : "none"}`);
    } catch (error) {
      log("CAMPAIGNS unreadable");
    }
    try {
      const rewards = await prisma.$queryRaw`SELECT COUNT(*)::int AS count FROM "IncentiveReward"`;
      log(`REWARD_ROWS ${rewards[0].count}`);
    } catch (error) {
      log("REWARD_ROWS unreadable");
    }
    try {
      const societies = await prisma.$queryRaw`SELECT COUNT(*)::int AS count FROM "Society"`;
      log(`SOCIETY_ROWS ${societies[0].count}`);
    } catch (error) {
      log("SOCIETY_ROWS unreadable");
    }
    try {
      const settings = await prisma.$queryRaw`SELECT COUNT(*)::int AS count FROM "AppSetting"`;
      log(`APP_SETTING_ROWS ${settings[0].count}`);
    } catch (error) {
      log("APP_SETTING_ROWS unreadable");
    }
    log("INSPECT_OK");
  } finally {
    if (prisma) await prisma.$disconnect();
  }
}

main().catch((error) => {
  const text = String(error && error.message ? error.message : "");
  let kind = "other";
  if (/authentication failed/i.test(text) || /password authentication failed/i.test(text)) kind = "authentication";
  else if (/does not exist/i.test(text)) kind = "database-missing";
  else if (/ECONNREFUSED/i.test(text) || /Can't reach database server/i.test(text)) kind = "unreachable";
  log(`INSPECT_KIND ${kind}`);
  process.exit(1);
});
