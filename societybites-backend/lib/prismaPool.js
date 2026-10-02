const DEFAULT_CONNECTION_LIMIT = "1";

/**
 * Supabase session pooler (port 5432) allows ~15 clients total. Prisma's
 * default pool is roughly `num_cpus * 2 + 1`, so one Node process can consume
 * the whole quota and My Kitchen starts returning 500s.
 */
function withPrismaPoolParams(rawUrl) {
  if (!rawUrl) return rawUrl;
  try {
    const url = new URL(rawUrl);
    if (url.port === "6543" && !url.searchParams.has("pgbouncer")) {
      url.searchParams.set("pgbouncer", "true");
    }
    if (!url.searchParams.has("connection_limit")) {
      url.searchParams.set(
        "connection_limit",
        process.env.PRISMA_CONNECTION_LIMIT || DEFAULT_CONNECTION_LIMIT
      );
    }
    return url.toString();
  } catch {
    return rawUrl;
  }
}

module.exports = { withPrismaPoolParams };
