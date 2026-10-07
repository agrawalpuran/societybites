const prisma = require("./prisma");

const FSSAI_REQUIREMENT_KEY = "fssai_selling_requirement";

async function isFssaiSellingRequirementEnabled() {
  const row = await prisma.appSetting.findUnique({
    where: { key: FSSAI_REQUIREMENT_KEY },
  });
  if (!row) return false;
  const normalized = String(row.value || "").trim().toLowerCase();
  return normalized === "on" || normalized === "true" || normalized === "1";
}

async function setFssaiSellingRequirement(enabled) {
  const value = enabled ? "on" : "off";
  await prisma.appSetting.upsert({
    where: { key: FSSAI_REQUIREMENT_KEY },
    update: { value },
    create: { key: FSSAI_REQUIREMENT_KEY, value },
  });
  return enabled;
}

module.exports = {
  FSSAI_REQUIREMENT_KEY,
  isFssaiSellingRequirementEnabled,
  setFssaiSellingRequirement,
};
