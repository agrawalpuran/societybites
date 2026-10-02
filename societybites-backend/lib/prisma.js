require("dotenv").config();
const { PrismaClient } = require("@prisma/client");
const { withPrismaPoolParams } = require("./prismaPool");

const databaseUrl = withPrismaPoolParams(process.env.DATABASE_URL);

const globalForPrisma = globalThis;
const prisma =
  globalForPrisma.__societybitesPrisma ||
  new PrismaClient(
    databaseUrl ? { datasources: { db: { url: databaseUrl } } } : undefined
  );

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.__societybitesPrisma = prisma;
}

module.exports = prisma;
