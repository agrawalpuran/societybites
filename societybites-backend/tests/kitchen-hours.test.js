const {
  assertKitchenHoursUpdate,
  isKitchenOpen,
  assertKitchenOpen,
  KITCHEN_CLOSED_MESSAGE,
} = require("../lib/kitchenHours");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function expectThrow(fn, statusCode, snippet) {
  try {
    fn();
    throw new Error("expected an error");
  } catch (err) {
    if (err.message === "expected an error") throw err;
    assert(err.statusCode === statusCode, `status ${err.statusCode} != ${statusCode}`);
    assert(
      String(err.message).includes(snippet),
      `message "${err.message}" did not include "${snippet}"`
    );
  }
}

function main() {
  const saved = assertKitchenHoursUpdate({
    opensAt: "9:00",
    closesAt: "21:05",
    role: "seller",
  });
  assert(saved.kitchenOpensAt === "09:00", "open time normalizes");
  assert(saved.kitchenClosesAt === "21:05", "close time normalizes");

  const cleared = assertKitchenHoursUpdate({
    opensAt: null,
    closesAt: "",
    role: "seller",
  });
  assert(cleared.kitchenOpensAt === null && cleared.kitchenClosesAt === null, "hours can clear");
  expectThrow(
    () => assertKitchenHoursUpdate({ opensAt: "09:00", closesAt: null, role: "seller" }),
    400,
    "both"
  );
  expectThrow(
    () => assertKitchenHoursUpdate({ opensAt: "09:00", closesAt: "09:00", role: "seller" }),
    400,
    "different"
  );
  expectThrow(
    () => assertKitchenHoursUpdate({ opensAt: "09:00", closesAt: "21:00", role: "buyer" }),
    400,
    "Enable selling"
  );

  const day = { kitchenOpensAt: "09:00", kitchenClosesAt: "21:00" };
  assert(isKitchenOpen(day, new Date("2026-10-04T04:00:00Z")), "09:30 IST is open");
  assert(!isKitchenOpen(day, new Date("2026-10-04T03:00:00Z")), "08:30 IST is closed");
  assert(!isKitchenOpen(day, new Date("2026-10-04T15:30:00Z")), "21:00 IST is closed");
  assert(isKitchenOpen(day, new Date("2026-10-04T15:29:00Z")), "20:59 IST is open");
  assert(isKitchenOpen({}, new Date("2026-10-04T03:00:00Z")), "unset hours stay open");
  assert(isKitchenOpen(null, new Date("2026-10-04T03:00:00Z")), "missing seller stays open");

  const overnight = { kitchenOpensAt: "18:00", kitchenClosesAt: "02:00" };
  assert(isKitchenOpen(overnight, new Date("2026-10-04T13:00:00Z")), "18:30 IST overnight is open");
  assert(isKitchenOpen(overnight, new Date("2026-10-04T20:00:00Z")), "01:30 IST overnight is open");
  assert(!isKitchenOpen(overnight, new Date("2026-10-04T21:00:00Z")), "02:30 IST overnight is closed");
  assert(!isKitchenOpen(overnight, new Date("2026-10-04T10:00:00Z")), "15:30 IST overnight is closed");

  expectThrow(() => assertKitchenOpen(day, new Date("2026-10-04T03:00:00Z")), 400, KITCHEN_CLOSED_MESSAGE);
  assertKitchenOpen(day, new Date("2026-10-04T04:00:00Z"));

  console.log("kitchen hours ok");
}

main();
