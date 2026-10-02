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

  console.log("prisma-pool tests passed");
}

main();
