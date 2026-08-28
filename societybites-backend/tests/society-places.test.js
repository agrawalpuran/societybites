const {
  isPrestigeNottingHillPlace,
  extractAddressParts,
  mapPlaceDetails,
  mapAutocompleteSuggestions,
  generateInviteCode,
  matchesDatabaseQuery,
  backfillData,
  previewSocietyFromPlace,
  findOrCreateSocietyFromPlace,
  PNH_SOCIETY_ID,
} = require("../lib/societyFromPlace");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function mockPrisma(seed = []) {
  const store = seed.map((row) => ({ blocks: [], ...row }));

  return {
    _store: store,
    society: {
      async findUnique({ where }) {
        if (where.googlePlaceId) {
          return (
            store.find((row) => row.googlePlaceId === where.googlePlaceId) ||
            null
          );
        }
        if (where.id) {
          return store.find((row) => row.id === where.id) || null;
        }
        if (where.inviteCode) {
          return store.find((row) => row.inviteCode === where.inviteCode) || null;
        }
        return null;
      },
      async create({ data }) {
        if (
          data.googlePlaceId &&
          store.some((row) => row.googlePlaceId === data.googlePlaceId)
        ) {
          const err = new Error("Unique constraint failed");
          err.code = "P2002";
          throw err;
        }
        const row = {
          id: `society-${store.length + 1}`,
          status: "active",
          unitLabel: "Block",
          blocks: [],
          ...data,
        };
        store.push(row);
        return row;
      },
      async update({ where, data }) {
        const row = store.find((item) => item.id === where.id);
        Object.assign(row, data);
        return row;
      },
    },
  };
}

const pnh = {
  id: PNH_SOCIETY_ID,
  name: "Prestige Notting Hill",
  city: "Bangalore",
  inviteCode: "PRESTIGE2026",
  googlePlaceId: null,
  latitude: null,
  longitude: null,
  address: "Bannerghatta Road",
  blocks: [{ id: "block-c", name: "C" }],
};

const pnhPlace = {
  placeId: "ChIJ-pnh-place",
  name: "Prestige Notting Hill",
  address: "Bannerghatta Road, Bengaluru, Karnataka, India",
  city: "Bengaluru",
  state: "Karnataka",
  pincode: "560076",
  latitude: 12.87,
  longitude: 77.59,
};

async function main() {
  assert(
    isPrestigeNottingHillPlace("Prestige Notting Hill Apartments"),
    "PNH name with Apartments should match"
  );
  assert(
    !isPrestigeNottingHillPlace("Spring Valley Apartments"),
    "unrelated name must not match PNH"
  );

  const parts = extractAddressParts([
    { longText: "Bengaluru", types: ["locality"] },
    { longText: "Karnataka", types: ["administrative_area_level_1"] },
    { longText: "560035", types: ["postal_code"] },
  ]);
  assert(parts.city === "Bengaluru", "city from locality");
  assert(parts.state === "Karnataka", "state from admin area");
  assert(parts.pincode === "560035", "pincode from postal_code");

  const noCity = extractAddressParts([
    { longText: "Karnataka", types: ["administrative_area_level_1"] },
  ]);
  assert(!noCity.city, "missing locality is not invented");

  const details = mapPlaceDetails({
    id: "ChIJ-spring",
    displayName: { text: "Spring Valley Apartments" },
    formattedAddress: "Sarjapur Road, Bengaluru",
    location: { latitude: 12.9, longitude: 77.7 },
    addressComponents: [
      { longText: "Bengaluru", types: ["locality"] },
      { longText: "Karnataka", types: ["administrative_area_level_1"] },
    ],
  });
  assert(details.placeId === "ChIJ-spring", "details placeId");
  assert(details.city === "Bengaluru", "details city");
  assert(details.latitude === 12.9, "details latitude");

  const suggestions = mapAutocompleteSuggestions({
    suggestions: [
      {
        placePrediction: {
          placeId: "ChIJ-spring",
          structuredFormat: {
            mainText: { text: "Spring Valley Apartments" },
            secondaryText: { text: "Sarjapur Road, Bengaluru" },
          },
        },
      },
    ],
  });
  assert(suggestions.length === 1, "one suggestion");
  assert(suggestions[0].name === "Spring Valley Apartments", "suggestion name");
  assert(!suggestions[0].id, "suggestions must not invent a SocietyBites id");

  const invite = generateInviteCode();
  assert(invite.length === 10, "invite code length");
  assert(/^[A-Z0-9]+$/.test(invite), "invite code charset");

  assert(
    matchesDatabaseQuery(pnh, "prestige"),
    "database fallback matches PNH name"
  );
  assert(
    matchesDatabaseQuery(pnh, "BANNERGHATTA"),
    "database fallback matches address"
  );
  assert(!matchesDatabaseQuery(pnh, "XYZABC123"), "unknown query is empty");

  const backfill = backfillData(pnh, pnhPlace);
  assert(backfill.googlePlaceId === pnhPlace.placeId, "backfill place id");
  assert(backfill.latitude === pnhPlace.latitude, "backfill latitude");
  assert(!backfill.city, "must not overwrite existing PNH city");
  assert(!backfill.name, "must not overwrite existing PNH name");

  const prisma = mockPrisma([pnh]);
  const preview = await previewSocietyFromPlace(prisma, pnhPlace, {
    persist: false,
  });
  assert(preview.society.id === PNH_SOCIETY_ID, "preview reuses PNH");
  assert(preview.isNew === false, "preview is not new");
  assert(prisma._store[0].googlePlaceId == null, "preview must not write PNH");

  const first = await findOrCreateSocietyFromPlace(prisma, pnhPlace);
  assert(first.id === PNH_SOCIETY_ID, "first resolve reuses PNH id");
  assert(first.googlePlaceId === pnhPlace.placeId, "first resolve backfills place id");
  assert(prisma._store.length === 1, "PNH must not be duplicated");

  const second = await findOrCreateSocietyFromPlace(prisma, pnhPlace);
  assert(second.id === PNH_SOCIETY_ID, "second resolve still PNH");
  assert(prisma._store.length === 1, "second resolve creates zero societies");

  const createPrisma = mockPrisma([]);
  const created = await findOrCreateSocietyFromPlace(createPrisma, {
    placeId: "ChIJ-spring-valley",
    name: "Spring Valley Apartments",
    address: "Sarjapur Road, Bengaluru",
    city: "Bengaluru",
    state: "Karnataka",
    pincode: "560035",
    latitude: 12.91,
    longitude: 77.68,
  });
  assert(created.id !== PNH_SOCIETY_ID, "new society gets a new id");
  assert(created.googlePlaceId === "ChIJ-spring-valley", "new society stores place id");
  assert(created.inviteCode && created.inviteCode.length === 10, "server invite code");
  assert(createPrisma._store.length === 1, "first new society +1");

  const reused = await findOrCreateSocietyFromPlace(createPrisma, {
    placeId: "ChIJ-spring-valley",
    name: "Spring Valley Apartments",
    address: "Sarjapur Road, Bengaluru",
    city: "Bengaluru",
    latitude: 12.91,
    longitude: 77.68,
  });
  assert(reused.id === created.id, "same place reuses society");
  assert(createPrisma._store.length === 1, "second user +0 societies");

  let cityError = null;
  try {
    await previewSocietyFromPlace(
      mockPrisma([]),
      {
        placeId: "ChIJ-no-city",
        name: "Mystery Towers",
        address: "Somewhere",
        city: "",
      },
      { persist: false }
    );
  } catch (err) {
    cityError = err;
  }
  assert(cityError && cityError.statusCode === 400, "missing city is 400");
  assert(
    cityError.message.includes("city"),
    "missing city uses a safe user-facing error"
  );

  console.log("society-places tests passed");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
