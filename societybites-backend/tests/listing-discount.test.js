const {
  quoteListingPrice,
  parseDiscountCreateFields,
  parseDiscountUpdateFields,
  serializeListingDiscount,
  orderItemDiscountSnapshot,
  money,
} = require("../lib/listingDiscount");
const { serializeListing } = require("../utils/listingSerializer");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function listing(overrides = {}) {
  return {
    price: 200,
    discountEnabled: false,
    discountPercent: null,
    discountStartsAt: null,
    discountEndsAt: null,
    name: "Test",
    seller: {},
    ...overrides,
  };
}

const off = quoteListingPrice(listing());
assert(off.discountActive === false, "legacy/disabled inactive");
assert(off.effectivePrice === 200, "legacy effective = regular");
assert(off.discountPercent === null, "inactive percent null");

const missing = quoteListingPrice({ price: 80 });
assert(missing.discountActive === false, "missing fields inactive");
assert(missing.effectivePrice === 80, "missing fields keep price");

let threw = false;
try {
  parseDiscountCreateFields({ discountEnabled: true, discountPercent: 0 });
} catch (err) {
  threw = err.statusCode === 400;
}
assert(threw, "percent 0 rejected");

threw = false;
try {
  parseDiscountCreateFields({ discountEnabled: true, discountPercent: 91 });
} catch (err) {
  threw = err.statusCode === 400;
}
assert(threw, "percent 91 rejected");

threw = false;
try {
  parseDiscountCreateFields({ discountEnabled: true, discountPercent: Number.NaN });
} catch (err) {
  threw = err.statusCode === 400;
}
assert(threw, "NaN rejected");

threw = false;
try {
  parseDiscountCreateFields({
    discountEnabled: true,
    discountPercent: Number.POSITIVE_INFINITY,
  });
} catch (err) {
  threw = err.statusCode === 400;
}
assert(threw, "Infinity rejected");

const one = parseDiscountCreateFields({
  discountEnabled: true,
  discountPercent: 1,
});
assert(one.discountPercent === 1, "percent 1 allowed");
const ninety = parseDiscountCreateFields({
  discountEnabled: true,
  discountPercent: 90,
});
assert(ninety.discountPercent === 90, "percent 90 allowed");

const createdOff = parseDiscountCreateFields({});
assert(createdOff.discountEnabled === false, "create default off");
assert(createdOff.discountPercent === null, "create default percent null");

const start = new Date("2026-10-23T10:00:00.000Z");
const end = new Date("2026-10-23T12:00:00.000Z");
threw = false;
try {
  parseDiscountCreateFields({
    discountEnabled: true,
    discountPercent: 10,
    discountStartsAt: end.toISOString(),
    discountEndsAt: start.toISOString(),
  });
} catch (err) {
  threw = err.statusCode === 400;
}
assert(threw, "end before start rejected");

const windowed = listing({
  discountEnabled: true,
  discountPercent: 10,
  discountStartsAt: start,
  discountEndsAt: end,
});
assert(
  quoteListingPrice(windowed, new Date("2026-10-23T09:59:59.999Z")).discountActive === false,
  "before start inactive"
);
assert(
  quoteListingPrice(windowed, start).discountActive === true,
  "at start active"
);
assert(
  quoteListingPrice(windowed, end).discountActive === true,
  "at end active"
);
assert(
  quoteListingPrice(windowed, new Date("2026-10-23T12:00:00.001Z")).discountActive === false,
  "after end inactive"
);

const open = listing({ discountEnabled: true, discountPercent: 10 });
assert(quoteListingPrice(open, start).discountActive === true, "missing dates unbounded");

assert(money(199 * 0.9) === 179.1, "money rounds to cents");
const odd = quoteListingPrice(
  listing({ price: 199, discountEnabled: true, discountPercent: 10 })
);
assert(odd.effectivePrice === 179.1, "10% of 199 uses money()");

const serializedOff = serializeListing(listing({ price: 150, seller: { id: "s" } }));
assert(serializedOff.price === 150, "serializer keeps regular price");
assert(serializedOff.effectivePrice === 150, "inactive effective = price");
assert(serializedOff.discountActive === false, "serializer inactive");

const serializedOn = serializeListing(
  listing({
    price: 200,
    discountEnabled: true,
    discountPercent: 10,
    seller: { id: "s" },
  })
);
assert(serializedOn.price === 200, "active still exposes regular price");
assert(serializedOn.effectivePrice === 180, "active effectivePrice");
assert(serializedOn.discountActive === true, "serializer active");
assert(serializedOn.discountPercent === 10, "configured percent");

const expired = serializeListingDiscount(
  listing({
    discountEnabled: true,
    discountPercent: 25,
    discountStartsAt: new Date("2020-01-01T00:00:00.000Z"),
    discountEndsAt: new Date("2020-01-02T00:00:00.000Z"),
  }),
  new Date("2026-10-23T00:00:00.000Z")
);
assert(expired.discountActive === false, "expired not active");
assert(expired.effectivePrice === 200, "expired effective = regular");

const snap = orderItemDiscountSnapshot(
  listing({ price: 200, discountEnabled: true, discountPercent: 10 })
);
assert(snap.unitPrice === 180, "snapshot charged price");
assert(snap.originalUnitPrice === 200, "snapshot regular");
assert(snap.discountPercent === 10, "snapshot percent");

const snapOff = orderItemDiscountSnapshot(listing({ price: 200 }));
assert(snapOff.unitPrice === 200, "no discount unit");
assert(snapOff.originalUnitPrice === 200, "no discount original");
assert(snapOff.discountPercent === null, "no discount percent");

const preserved = parseDiscountUpdateFields({ name: "x" }, listing({
  discountEnabled: true,
  discountPercent: 15,
}));
assert(preserved === undefined, "omission does not produce update fields");

const patched = parseDiscountUpdateFields(
  { discountEnabled: true, discountPercent: 20 },
  listing({ discountEnabled: false, discountPercent: null })
);
assert(patched.discountEnabled === true, "update enables");
assert(patched.discountPercent === 20, "update percent");

console.log("listing-discount.test.js ok");
