const prisma = require("./prisma");
const { refreshServingCities } = require("./servingCities");
const { getPlaceDetails } = require("./placesGoogle");
const {
  mapPlaceDetails,
  findOrCreateSocietyFromPlace,
} = require("./societyFromPlace");

const MAX_PLACES = 8;

const addressInclude = {
  society: { select: { id: true, name: true, city: true } },
  flat: { select: { id: true, block: true, flatNumber: true } },
};

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function assertBuyer(user) {
  if (!user) throw httpError(401, "Sign in to manage places");
  const role = user.role;
  if (role !== "buyer" && role !== "admin" && role !== "super_admin") {
    throw httpError(403, "Saved places are available for buyers");
  }
}

function normalizeLabel(value) {
  const label = String(value || "").trim().replace(/\s+/g, " ");
  if (!label) throw httpError(400, "Name this place");
  if (label.length > 40) throw httpError(400, "Use a shorter name");
  return label;
}

function parseFloorUnit(flatNumber) {
  const digits = String(flatNumber).replace(/\D/g, "");
  if (digits.length >= 4) {
    return {
      floor: parseInt(digits.substring(1, 3), 10) || 0,
      unit: digits.slice(-1),
    };
  }
  if (digits.length >= 2) {
    return {
      floor: parseInt(digits.slice(0, -1), 10) || 0,
      unit: digits.slice(-1),
    };
  }
  return { floor: 0, unit: String(flatNumber).trim() || "1" };
}

function serializeAddress(row) {
  return {
    id: row.id,
    label: row.label,
    societyId: row.societyId,
    flatId: row.flatId,
    block: row.block || row.flat?.block || null,
    flatNumber: row.flatNumber || row.flat?.flatNumber || null,
    selected: row.selected === true,
    society: row.society
      ? {
          id: row.society.id,
          name: row.society.name,
          city: row.society.city,
        }
      : null,
  };
}

function serializePlace(user) {
  return {
    societyId: user.societyId,
    flatId: user.flatId,
    society: user.society
      ? {
          id: user.society.id,
          name: user.society.name,
          city: user.society.city,
        }
      : null,
    flat: user.flat
      ? {
          id: user.flat.id,
          block: user.flat.block,
          flatNumber: user.flat.flatNumber,
        }
      : null,
  };
}

async function loadAddresses(userId) {
  const rows = await prisma.buyerAddress.findMany({
    where: { userId },
    include: addressInclude,
    orderBy: { createdAt: "asc" },
  });
  return rows.map(serializeAddress);
}

async function ensureSavedPlaces(user) {
  const existing = await prisma.buyerAddress.count({ where: { userId: user.id } });
  if (existing > 0 || !user.societyId) return;

  const flat = user.flatId
    ? await prisma.flat.findUnique({ where: { id: user.flatId } })
    : null;
  await prisma.buyerAddress.create({
    data: {
      userId: user.id,
      label: "Home",
      societyId: user.societyId,
      flatId: flat ? flat.id : null,
      block: flat ? flat.block : null,
      flatNumber: flat ? flat.flatNumber : null,
      selected: true,
    },
  });
}

async function resolveSociety(body) {
  const societyId = body && body.societyId ? String(body.societyId).trim() : "";
  const inviteCode = body && body.inviteCode ? String(body.inviteCode).trim() : "";
  const googlePlaceId =
    body && body.googlePlaceId ? String(body.googlePlaceId).trim() : "";
  if (!societyId && !inviteCode && !googlePlaceId) {
    throw httpError(400, "Choose a society");
  }

  let society = null;
  if (googlePlaceId) {
    await refreshServingCities();
    const details = mapPlaceDetails(await getPlaceDetails(googlePlaceId));
    society = await findOrCreateSocietyFromPlace(prisma, details);
  } else if (societyId) {
    society = await prisma.society.findUnique({ where: { id: societyId } });
  } else {
    society = await prisma.society.findFirst({
      where: { inviteCode: { equals: inviteCode, mode: "insensitive" } },
    });
  }

  if (!society) {
    throw httpError(
      400,
      inviteCode && !societyId && !googlePlaceId
        ? "Invalid invite code"
        : "Society not found"
    );
  }
  if (society.status !== "active") {
    throw httpError(400, "This society is not accepting new members");
  }
  return society;
}

async function resolveOptionalFlat(societyId, body) {
  const flatNumber = body && body.flatNumber ? String(body.flatNumber).trim() : "";
  const block = body && body.block ? String(body.block).trim() : "";
  if (!flatNumber && !block) return null;
  if (!flatNumber || !block) {
    throw httpError(400, "Enter both block and flat, or leave both empty");
  }

  const { floor, unit } = parseFloorUnit(flatNumber);
  const existing = await prisma.flat.findUnique({
    where: { societyId_flatNumber: { societyId, flatNumber } },
  });
  if (!existing) {
    return prisma.flat.create({
      data: { societyId, flatNumber, block, floor, unit },
    });
  }
  if (existing.block !== block) {
    return prisma.flat.update({
      where: { id: existing.id },
      data: { block },
    });
  }
  return existing;
}

async function listBuyerAddresses(user) {
  assertBuyer(user);
  const rows = await prisma.buyerAddress.findMany({
    where: { userId: user.id },
    include: addressInclude,
    orderBy: { createdAt: "asc" },
  });
  if (rows.length > 0) {
    return { addresses: rows.map(serializeAddress) };
  }
  if (!user.societyId) return { addresses: [] };

  const flat = user.flatId
    ? await prisma.flat.findUnique({ where: { id: user.flatId } })
    : null;
  const created = await prisma.buyerAddress.create({
    data: {
      userId: user.id,
      label: "Home",
      societyId: user.societyId,
      flatId: flat ? flat.id : null,
      block: flat ? flat.block : null,
      flatNumber: flat ? flat.flatNumber : null,
      selected: true,
    },
    include: addressInclude,
  });
  return { addresses: [serializeAddress(created)] };
}

async function addBuyerAddress(user, body) {
  assertBuyer(user);
  const label = normalizeLabel(body && body.label);
  const society = await resolveSociety(body || {});
  const flat = await resolveOptionalFlat(society.id, body || {});

  await ensureSavedPlaces(user);
  const count = await prisma.buyerAddress.count({ where: { userId: user.id } });
  if (count >= MAX_PLACES) {
    throw httpError(400, "You can save up to 8 places");
  }

  const selectThis = count === 0;
  await prisma.$transaction(async (tx) => {
    await tx.buyerAddress.create({
      data: {
        userId: user.id,
        label,
        societyId: society.id,
        flatId: flat ? flat.id : null,
        block: flat ? flat.block : null,
        flatNumber: flat ? flat.flatNumber : null,
        selected: selectThis,
      },
    });
    if (selectThis) {
      await tx.user.update({
        where: { id: user.id },
        data: { societyId: society.id, flatId: flat ? flat.id : null },
      });
    }
  });
  return { addresses: await loadAddresses(user.id) };
}

async function selectBuyerAddress(user, addressId) {
  assertBuyer(user);
  const row = await prisma.buyerAddress.findFirst({
    where: { id: String(addressId), userId: user.id },
  });
  if (!row) throw httpError(404, "Place not found");

  await prisma.$transaction([
    prisma.buyerAddress.updateMany({
      where: { userId: user.id },
      data: { selected: false },
    }),
    prisma.buyerAddress.update({
      where: { id: row.id },
      data: { selected: true },
    }),
    prisma.user.update({
      where: { id: user.id },
      data: { societyId: row.societyId, flatId: row.flatId },
    }),
  ]);

  const refreshed = await prisma.user.findUnique({
    where: { id: user.id },
    include: { society: true, flat: true },
  });
  return {
    addresses: await loadAddresses(user.id),
    place: serializePlace(refreshed),
  };
}

async function deleteBuyerAddress(user, addressId) {
  assertBuyer(user);
  const row = await prisma.buyerAddress.findFirst({
    where: { id: String(addressId), userId: user.id },
  });
  if (!row) throw httpError(404, "Place not found");
  if (row.selected) {
    throw httpError(400, "Choose another place before removing this one");
  }
  await prisma.buyerAddress.delete({ where: { id: row.id } });
  return { addresses: await loadAddresses(user.id) };
}

module.exports = {
  listBuyerAddresses,
  addBuyerAddress,
  selectBuyerAddress,
  deleteBuyerAddress,
  resolveSociety,
  resolveOptionalFlat,
};
