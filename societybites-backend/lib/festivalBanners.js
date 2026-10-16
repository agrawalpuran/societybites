const prisma = require("./prisma");

const PLACEMENTS = new Set(["BELOW_SEARCH", "BELOW_CATEGORIES"]);
const STATUSES = new Set(["DRAFT", "ACTIVE", "INACTIVE"]);

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function trimText(value, { max = 200, field = "field" } = {}) {
  if (value == null) return null;
  const text = String(value).trim();
  if (!text) return null;
  if (text.length > max) throw httpError(400, `${field} is too long`);
  return text;
}

function assertPlacement(value) {
  const placement = String(value || "BELOW_SEARCH").trim().toUpperCase();
  if (!PLACEMENTS.has(placement)) {
    throw httpError(400, "Invalid banner placement");
  }
  return placement;
}

function assertImageUrl(value) {
  if (value == null || String(value).trim() === "") return null;
  const text = String(value).trim();
  if (text.length > 2000 || !/^https:\/\//i.test(text)) {
    throw httpError(400, "Banner image URL is invalid");
  }
  return text;
}

function parseOptionalDate(value, field) {
  if (value == null || value === "") return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw httpError(400, `${field} is invalid`);
  }
  return date;
}

function serializeBanner(row) {
  if (!row) return null;
  return {
    id: row.id,
    name: row.name,
    title: row.title,
    subtitle: row.subtitle,
    imageUrl: row.imageUrl,
    placement: row.placement,
    status: row.status,
    startsAt: row.startsAt,
    endsAt: row.endsAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}

function isWithinSchedule(row, now = new Date()) {
  if (row.startsAt && now < row.startsAt) return false;
  if (row.endsAt && now > row.endsAt) return false;
  return true;
}

function buildBannerData(body, { partial = false } = {}) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw httpError(400, "JSON body is required");
  }
  const data = {};
  if (!partial || body.name !== undefined) {
    const name = trimText(body.name, { max: 120, field: "name" });
    if (!name) throw httpError(400, "name is required");
    data.name = name;
  }
  if (!partial || body.title !== undefined) {
    data.title = trimText(body.title, { max: 120, field: "title" });
  }
  if (!partial || body.subtitle !== undefined) {
    data.subtitle = trimText(body.subtitle, { max: 240, field: "subtitle" });
  }
  if (!partial || body.imageUrl !== undefined) {
    data.imageUrl = assertImageUrl(body.imageUrl);
  }
  if (!partial || body.placement !== undefined) {
    data.placement = assertPlacement(body.placement);
  }
  if (!partial || body.startsAt !== undefined) {
    data.startsAt = parseOptionalDate(body.startsAt, "startsAt");
  }
  if (!partial || body.endsAt !== undefined) {
    data.endsAt = parseOptionalDate(body.endsAt, "endsAt");
  }
  if (
    data.startsAt &&
    data.endsAt &&
    data.endsAt.getTime() < data.startsAt.getTime()
  ) {
    throw httpError(400, "endsAt must be on or after startsAt");
  }
  if (!data.imageUrl && !data.title && !data.subtitle && !partial) {
    throw httpError(400, "Add a title, subtitle, or image for the banner");
  }
  return data;
}

async function getActiveFestivalBanner(now = new Date()) {
  const rows = await prisma.festivalBanner.findMany({
    where: { status: "ACTIVE" },
    orderBy: { updatedAt: "desc" },
    take: 5,
  });
  const active = rows.find((row) => isWithinSchedule(row, now));
  return serializeBanner(active || null);
}

async function listFestivalBanners() {
  const rows = await prisma.festivalBanner.findMany({
    orderBy: [{ status: "asc" }, { updatedAt: "desc" }],
  });
  return rows.map(serializeBanner);
}

async function getFestivalBanner(id) {
  const row = await prisma.festivalBanner.findUnique({ where: { id: String(id) } });
  if (!row) throw httpError(404, "Festival banner not found");
  return serializeBanner(row);
}

async function createFestivalBanner(body) {
  const data = buildBannerData(body, { partial: false });
  const row = await prisma.festivalBanner.create({
    data: {
      ...data,
      status: "DRAFT",
    },
  });
  return serializeBanner(row);
}

async function updateFestivalBanner(id, body) {
  const existing = await prisma.festivalBanner.findUnique({
    where: { id: String(id) },
  });
  if (!existing) throw httpError(404, "Festival banner not found");
  const data = buildBannerData(
    {
      name: body.name !== undefined ? body.name : existing.name,
      title: body.title !== undefined ? body.title : existing.title,
      subtitle: body.subtitle !== undefined ? body.subtitle : existing.subtitle,
      imageUrl: body.imageUrl !== undefined ? body.imageUrl : existing.imageUrl,
      placement:
        body.placement !== undefined ? body.placement : existing.placement,
      startsAt: body.startsAt !== undefined ? body.startsAt : existing.startsAt,
      endsAt: body.endsAt !== undefined ? body.endsAt : existing.endsAt,
    },
    { partial: false }
  );
  const row = await prisma.festivalBanner.update({
    where: { id: existing.id },
    data,
  });
  return serializeBanner(row);
}

async function activateFestivalBanner(id, adminUser) {
  const existing = await prisma.festivalBanner.findUnique({
    where: { id: String(id) },
  });
  if (!existing) throw httpError(404, "Festival banner not found");
  if (!existing.imageUrl && !existing.title && !existing.subtitle) {
    throw httpError(400, "Add a title, subtitle, or image before activating");
  }

  const row = await prisma.$transaction(async (tx) => {
    await tx.festivalBanner.updateMany({
      where: { status: "ACTIVE", NOT: { id: existing.id } },
      data: { status: "INACTIVE" },
    });
    const updated = await tx.festivalBanner.update({
      where: { id: existing.id },
      data: { status: "ACTIVE" },
    });
    if (adminUser && adminUser.id) {
      await tx.auditLog.create({
        data: {
          adminId: adminUser.id,
          action: "FESTIVAL_BANNER_ACTIVATE",
          target: existing.id,
          details: JSON.stringify({ name: existing.name }),
        },
      });
    }
    return updated;
  });
  return serializeBanner(row);
}

async function deactivateFestivalBanner(id, adminUser) {
  const existing = await prisma.festivalBanner.findUnique({
    where: { id: String(id) },
  });
  if (!existing) throw httpError(404, "Festival banner not found");
  const row = await prisma.$transaction(async (tx) => {
    const updated = await tx.festivalBanner.update({
      where: { id: existing.id },
      data: { status: "INACTIVE" },
    });
    if (adminUser && adminUser.id) {
      await tx.auditLog.create({
        data: {
          adminId: adminUser.id,
          action: "FESTIVAL_BANNER_DEACTIVATE",
          target: existing.id,
          details: JSON.stringify({ name: existing.name }),
        },
      });
    }
    return updated;
  });
  return serializeBanner(row);
}

module.exports = {
  PLACEMENTS,
  STATUSES,
  getActiveFestivalBanner,
  listFestivalBanners,
  getFestivalBanner,
  createFestivalBanner,
  updateFestivalBanner,
  activateFestivalBanner,
  deactivateFestivalBanner,
  serializeBanner,
  isWithinSchedule,
};
