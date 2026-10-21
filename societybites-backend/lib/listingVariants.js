const { randomUUID } = require("crypto");
const { resolveListingQuantity } = require("./listingAvailability");

const VARIANT_INVENTORY_SEPARATE = "SEPARATE";
const VARIANT_INVENTORY_SHARED = "SHARED";

/** Convert human amounts (kg, L, …) into integer base units (g, ml, count). */
const INVENTORY_UNITS = {
  grams: { family: "mass", toBase: 1, short: "g" },
  g: { family: "mass", toBase: 1, short: "g" },
  kg: { family: "mass", toBase: 1000, short: "kg" },
  ml: { family: "volume", toBase: 1, short: "ml" },
  litres: { family: "volume", toBase: 1000, short: "L" },
  liters: { family: "volume", toBase: 1000, short: "L" },
  l: { family: "volume", toBase: 1000, short: "L" },
  portions: { family: "count", toBase: 1, short: "portions" },
  pieces: { family: "count", toBase: 1, short: "pcs" },
  packs: { family: "count", toBase: 1, short: "packs" },
};

function resolveInventoryUnit(raw) {
  const key = String(raw || "")
    .trim()
    .toLowerCase();
  return INVENTORY_UNITS[key] || null;
}

function amountToBaseUnits(amountRaw, unitRaw, fieldLabel) {
  const amount = Number(amountRaw);
  if (!Number.isFinite(amount) || amount <= 0) {
    const err = new Error(`${fieldLabel} must be greater than 0`);
    err.statusCode = 400;
    throw err;
  }
  const unit = resolveInventoryUnit(unitRaw);
  if (!unit) {
    const err = new Error(
      `${fieldLabel}: choose a unit (g, kg, ml, L, portions, pieces, packs)`
    );
    err.statusCode = 400;
    throw err;
  }
  const base = Math.round(amount * unit.toBase);
  if (!Number.isFinite(base) || base < 1) {
    const err = new Error(`${fieldLabel} is too small after unit conversion`);
    err.statusCode = 400;
    throw err;
  }
  if (base > 100000000) {
    const err = new Error(`${fieldLabel} is too large`);
    err.statusCode = 400;
    throw err;
  }
  return { base, unit, amount };
}

function normalizeVariantInventoryMode(raw) {
  const value = String(raw || "")
    .trim()
    .toUpperCase();
  if (!value || value === VARIANT_INVENTORY_SEPARATE) {
    return VARIANT_INVENTORY_SEPARATE;
  }
  if (value === VARIANT_INVENTORY_SHARED) {
    return VARIANT_INVENTORY_SHARED;
  }
  const err = new Error(
    'Inventory mode must be "SEPARATE" (each size has stock) or "SHARED" (one pool)'
  );
  err.statusCode = 400;
  throw err;
}

function isSharedVariantInventory(listing) {
  return (
    Boolean(listing) &&
    listing.variantInventoryMode === VARIANT_INVENTORY_SHARED &&
    Number.isFinite(Number(listing.portionUnits)) &&
    Number(listing.portionUnits) >= 1
  );
}

/** How many of this size can still be ordered from the shared pool. */
function orderableQuantity(listing) {
  if (!listing) return 0;
  const pool = Number(listing.quantity) || 0;
  if (isSharedVariantInventory(listing)) {
    const units = Number(listing.portionUnits);
    return Math.floor(pool / units);
  }
  return pool;
}

function sharedPoolCost(listing, orderQty) {
  const qty = Number(orderQty);
  if (!Number.isFinite(qty) || qty < 1) {
    const err = new Error("Each item needs quantity >= 1");
    err.statusCode = 400;
    throw err;
  }
  if (!isSharedVariantInventory(listing)) {
    return qty;
  }
  return Number(listing.portionUnits) * qty;
}

function parsePortionUnits(raw, label) {
  const n = parseInt(raw, 10);
  if (!Number.isFinite(n) || n < 1) {
    const err = new Error(
      `Size "${label}" needs a portion size of at least 1 (how much of the pool one order uses)`
    );
    err.statusCode = 400;
    throw err;
  }
  if (n > 1000000) {
    const err = new Error(`Size "${label}": portion size is too large`);
    err.statusCode = 400;
    throw err;
  }
  return n;
}

function parseVariantLabel(row, index) {
  const label = String(row?.label || "").trim();
  if (!label) {
    const err = new Error(`Size ${index + 1} needs a label`);
    err.statusCode = 400;
    throw err;
  }
  if (label.length > 40) {
    const err = new Error(`Size label must be at most 40 characters`);
    err.statusCode = 400;
    throw err;
  }
  return label;
}

function parseVariantPrice(row, label) {
  const price = parseFloat(row?.price);
  if (!Number.isFinite(price) || price < 0) {
    const err = new Error(`Size "${label}" needs a valid price`);
    err.statusCode = 400;
    throw err;
  }
  return price;
}

function parseWeightFields(row) {
  const weightValue = row?.weightValue
    ? String(row.weightValue).trim() || null
    : null;
  const weightUnit = row?.weightUnit
    ? String(row.weightUnit).trim() || null
    : null;
  return { weightValue, weightUnit };
}

/**
 * Parse optional variants + inventory mode from create-listing body.
 * Returns null when the seller is publishing a single SKU.
 * @returns {{ mode: string, poolQuantity: number|null, rows: object[] }|null}
 */
function parseVariantCreatePayload({
  variants: raw,
  variantInventoryMode,
  sharedPoolQuantity,
  sharedPoolUnit,
}) {
  if (raw == null) return null;
  if (!Array.isArray(raw)) {
    const err = new Error("variants must be an array");
    err.statusCode = 400;
    throw err;
  }
  if (raw.length === 0) return null;
  if (raw.length < 2) {
    const err = new Error(
      "Add at least two sizes, or leave sizes empty for a single listing"
    );
    err.statusCode = 400;
    throw err;
  }
  if (raw.length > 8) {
    const err = new Error("At most 8 sizes per listing");
    err.statusCode = 400;
    throw err;
  }

  const mode = normalizeVariantInventoryMode(variantInventoryMode);

  if (mode === VARIANT_INVENTORY_SHARED) {
    // Prefer amount+unit (10 kg + 250 g). Fall back to already-converted base ints.
    let poolQuantity;
    let poolFamily = null;
    if (sharedPoolUnit) {
      const converted = amountToBaseUnits(
        sharedPoolQuantity,
        sharedPoolUnit,
        "Total available"
      );
      poolQuantity = converted.base;
      poolFamily = converted.unit.family;
    } else {
      try {
        poolQuantity = resolveListingQuantity(sharedPoolQuantity);
      } catch (err) {
        err.message = `Total available: ${err.message}`;
        throw err;
      }
    }

    const rows = raw.map((row, index) => {
      const price = parseVariantPrice(row, `Size ${index + 1}`);
      let portionUnits;
      let displayAmount;
      let displayUnit;
      const portionUnitRaw = row?.portionUnit || row?.weightUnit;
      if (portionUnitRaw) {
        const converted = amountToBaseUnits(
          row?.portionAmount ?? row?.portionUnits ?? row?.quantity,
          portionUnitRaw,
          `Size ${index + 1} portion`
        );
        if (poolFamily && converted.unit.family !== poolFamily) {
          const err = new Error(
            `Size ${index + 1}: use the same kind of unit as the pool (weight with weight, volume with volume)`
          );
          err.statusCode = 400;
          throw err;
        }
        if (!poolFamily) poolFamily = converted.unit.family;
        portionUnits = converted.base;
        displayAmount = converted.amount;
        displayUnit = portionUnitRaw;
      } else {
        portionUnits = parsePortionUnits(
          row?.portionUnits ?? row?.quantity,
          `Size ${index + 1}`
        );
        displayAmount = portionUnits;
        displayUnit = row?.weightUnit || null;
      }

      if (portionUnits > poolQuantity) {
        const err = new Error(
          `Size ${index + 1} portion cannot exceed total available after converting units`
        );
        err.statusCode = 400;
        throw err;
      }

      const autoLabel =
        displayUnit && Number.isFinite(Number(displayAmount))
          ? `${displayAmount} ${resolveInventoryUnit(displayUnit)?.short || displayUnit}`
          : null;
      let label;
      try {
        label = parseVariantLabel(
          { label: row?.label || autoLabel },
          index
        );
      } catch (err) {
        if (autoLabel) {
          label = autoLabel.slice(0, 40);
        } else {
          throw err;
        }
      }

      const { weightValue, weightUnit } = parseWeightFields(row);
      return {
        variantLabel: label,
        price,
        quantity: poolQuantity,
        portionUnits,
        weightValue:
          weightValue ||
          (displayAmount != null ? String(displayAmount) : String(portionUnits)),
        weightUnit: weightUnit || displayUnit || null,
        variantInventoryMode: mode,
      };
    });
    return { mode, poolQuantity, rows };
  }

  const rows = raw.map((row, index) => {
    const label = parseVariantLabel(row, index);
    const price = parseVariantPrice(row, label);
    let quantity;
    try {
      quantity = resolveListingQuantity(row?.quantity ?? 1);
    } catch (err) {
      err.message = `Size "${label}": ${err.message}`;
      throw err;
    }
    const { weightValue, weightUnit } = parseWeightFields(row);
    return {
      variantLabel: label,
      price,
      quantity,
      portionUnits: null,
      weightValue,
      weightUnit,
      variantInventoryMode: mode,
    };
  });
  return { mode, poolQuantity: null, rows };
}

/** @deprecated Use parseVariantCreatePayload — kept for older unit tests. */
function parseVariantCreateRows(raw) {
  const parsed = parseVariantCreatePayload({
    variants: raw,
    variantInventoryMode: VARIANT_INVENTORY_SEPARATE,
  });
  return parsed ? parsed.rows : null;
}

function newVariantGroupId() {
  return randomUUID();
}

/** Sort siblings for buyer chips: cheaper first, then label. */
function sortVariantSiblings(listings) {
  return [...listings].sort((a, b) => {
    const byPrice = (a.price || 0) - (b.price || 0);
    if (byPrice !== 0) return byPrice;
    return String(a.variantLabel || "").localeCompare(String(b.variantLabel || ""));
  });
}

/**
 * Atomically reserve from a SHARED pool: decrement every sibling by cost.
 * Returns refreshed primary listing row.
 */
async function reserveSharedPool(tx, listing, orderQty) {
  const cost = sharedPoolCost(listing, orderQty);
  const groupId = listing.variantGroupId;
  if (!groupId) {
    const err = new Error("Shared inventory listing is missing a size group");
    err.statusCode = 500;
    throw err;
  }

  const siblingWhere = {
    variantGroupId: groupId,
    status: { in: ["active", "sold_out", "paused"] },
  };
  const siblingCount = await tx.listing.count({ where: siblingWhere });
  const updated = await tx.listing.updateMany({
    where: {
      ...siblingWhere,
      quantity: { gte: cost },
    },
    data: {
      quantity: { decrement: cost },
    },
  });
  if (updated.count !== siblingCount) {
    const latest = await tx.listing.findUnique({
      where: { id: listing.id },
      select: { quantity: true, portionUnits: true, name: true },
    });
    const available = orderableQuantity({
      ...latest,
      variantInventoryMode: VARIANT_INVENTORY_SHARED,
    });
    const err = new Error(
      available === 0
        ? `"${listing.name}" is sold out`
        : `Only ${available} portions are available for "${listing.name}".`
    );
    err.statusCode = 409;
    err.availableQuantity = available;
    throw err;
  }

  const refreshed = await tx.listing.findUnique({ where: { id: listing.id } });
  const siblings = await tx.listing.findMany({
    where: { variantGroupId: groupId },
    select: { id: true, portionUnits: true, quantity: true },
  });
  for (const sibling of siblings) {
    const orderable = orderableQuantity({
      ...sibling,
      variantInventoryMode: VARIANT_INVENTORY_SHARED,
    });
    if (orderable <= 0 && sibling.quantity != null) {
      await tx.listing.update({
        where: { id: sibling.id },
        data: { status: "sold_out" },
      });
    }
  }
  return refreshed;
}

async function restoreSharedPool(tx, listing, orderQty) {
  const cost = sharedPoolCost(listing, orderQty);
  const groupId = listing.variantGroupId;
  if (!groupId) {
    await tx.listing.update({
      where: { id: listing.id },
      data: {
        quantity: { increment: cost },
        status: "active",
      },
    });
    return;
  }
  await tx.listing.updateMany({
    where: { variantGroupId: groupId },
    data: {
      quantity: { increment: cost },
      status: "active",
    },
  });
}

module.exports = {
  VARIANT_INVENTORY_SEPARATE,
  VARIANT_INVENTORY_SHARED,
  normalizeVariantInventoryMode,
  isSharedVariantInventory,
  orderableQuantity,
  sharedPoolCost,
  parseVariantCreatePayload,
  parseVariantCreateRows,
  newVariantGroupId,
  sortVariantSiblings,
  reserveSharedPool,
  restoreSharedPool,
};
