const { withPrismaPoolParams } = require("../lib/prismaPool");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function main() {
  const session = withPrismaPoolParams(
    "postgresql://u:p@host.pooler.supabase.com:5432/postgres"
  );
  assert(
    session.includes("connection_limit=1"),
    `session URL should cap pool, got ${session}`
  );
  assert(
    !session.includes("pgbouncer"),
    "session pooler should not force pgbouncer"
  );

  const txn = withPrismaPoolParams(
    "postgresql://u:p@host.pooler.supabase.com:6543/postgres"
  );
  assert(txn.includes("pgbouncer=true"), "transaction pooler needs pgbouncer");
  assert(txn.includes("connection_limit=1"), "transaction pooler should cap pool");

  const already = withPrismaPoolParams(
    "postgresql://u:p@host:6543/postgres?pgbouncer=true&connection_limit=3"
  );
  assert(
    already.includes("connection_limit=3") &&
      !already.includes("connection_limit=1"),
    "existing connection_limit must be kept"
  );

  const productionLike = withPrismaPoolParams(
    "postgresql://u:p@aws-1-ap-south-1.pooler.supabase.com:6543/postgres?pgbouncer=true&connection_limit=6&pool_timeout=20"
  );
  assert(
    productionLike.includes("connection_limit=6"),
    "explicit connection_limit=6 must be preserved"
  );
  assert(
    productionLike.includes("pool_timeout=20"),
    "explicit pool_timeout must be preserved"
  );
  assert(
    productionLike.includes("pgbouncer=true"),
    "existing pgbouncer=true must be preserved"
  );

  const empty = withPrismaPoolParams("");
  assert(empty === "", "empty URL stays empty");

  const missing = withPrismaPoolParams(undefined);
  assert(missing === undefined, "undefined URL stays undefined");

  const garbage = withPrismaPoolParams("not-a-url");
  assert(garbage === "not-a-url", "invalid URL is returned unchanged");

  const prev = process.env.PRISMA_CONNECTION_LIMIT;
  process.env.PRISMA_CONNECTION_LIMIT = "5";
  try {
    const fromEnv = withPrismaPoolParams(
      "postgresql://u:p@host.pooler.supabase.com:6543/postgres"
    );
    assert(
      fromEnv.includes("connection_limit=5"),
      "PRISMA_CONNECTION_LIMIT should apply when URL has no limit"
    );
  } finally {
    if (prev === undefined) delete process.env.PRISMA_CONNECTION_LIMIT;
    else process.env.PRISMA_CONNECTION_LIMIT = prev;
  }

  console.log("prisma-pool tests passed");
}

main();
