const {
  suggestionMatchesLaunchCity,
  societyMatchesLaunchCity,
  placeMatchesLaunchCity,
} = require("../lib/launchCity");
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

  const bengaluruMantri = {
    placeId: "ChIJ-mantri-blr",
    name: "Mantri Residency",
    address: "Bannerghatta Road, Kalena Agrahara, Bengaluru, Karnataka, India",
  };
  const puneMantri = {
    placeId: "ChIJ-mantri-pune",
    name: "Mantri Residency",
    address: "Baner, Pune, Maharashtra, India",
  };
  const hyderabadOnly = {
    placeId: "ChIJ-hyd",
    name: "My Home Bhooja",
    address: "Gachibowli, Hyderabad, Telangana, India",
  };
  const bangaloreVariant = {
    placeId: "ChIJ-blr-variant",
    name: "Spring Valley Apartments",
    address: "Sarjapur Road, Bangalore, Karnataka, India",
  };

  assert(
    suggestionMatchesLaunchCity(bengaluruMantri),
    "Bengaluru Mantri Residency is kept"
  );
  assert(
    !suggestionMatchesLaunchCity(puneMantri),
    "Pune Mantri Residency is dropped"
  );
  assert(
    !suggestionMatchesLaunchCity(hyderabadOnly),
    "Hyderabad-only society is dropped"
  );
  assert(
    suggestionMatchesLaunchCity(bangaloreVariant),
    "Bangalore is accepted as Bengaluru"
  );
  assert(
    suggestionMatchesLaunchCity({
      name: "New Bengaluru Society",
      address: "Whitefield, Bengaluru, Karnataka, India",
    }),
    "Bengaluru society not in DB is still returned"
  );
  assert(
    !suggestionMatchesLaunchCity({
      name: "Ambiguous Towers",
      address: "Karnataka, India",
    }),
    "ambiguous city is omitted from search"
  );

  const puneDb = {
    id: "mantri-pune",
    name: "Mantri Residency",
    city: "Pune",
    address: "Baner",
  };
  assert(
    matchesDatabaseQuery(puneDb, "mantri"),
    "name still matches for fallback input"
  );
  assert(
    !societyMatchesLaunchCity(puneDb),
    "DB fallback drops Pune even when the name matches"
  );
  assert(
    societyMatchesLaunchCity(pnh),
    "DB fallback keeps Bangalore PNH"
  );

  assert(
    placeMatchesLaunchCity({ city: "Bangalore", state: "Karnataka" }),
    "Bangalore locality is launch city"
  );
  assert(
    placeMatchesLaunchCity({
      city: "",
      district: "Bengaluru Urban",
      address: "Bengaluru Urban, Karnataka, India",
    }),
    "Bengaluru Urban district is launch city"
  );
  assert(
    !placeMatchesLaunchCity({ city: "Pune", state: "Maharashtra" }),
    "Pune locality is outside launch city"
  );

  let puneCreateError = null;
  try {
    await findOrCreateSocietyFromPlace(mockPrisma([]), {
      placeId: "ChIJ-pune-place",
      name: "Mantri Residency",
      address: "Baner, Pune, Maharashtra, India",
      city: "Pune",
      state: "Maharashtra",
      latitude: 18.5,
      longitude: 73.8,
    });
  } catch (err) {
    puneCreateError = err;
  }
  assert(puneCreateError && puneCreateError.statusCode === 400, "Pune confirm is 400");
  assert(
    puneCreateError.code === "LAUNCH_CITY_UNAVAILABLE",
    "Pune confirm uses launch-city error"
  );
  assert(
    /Bengaluru/.test(puneCreateError.message),
    "Pune confirm names the launch city"
  );
  assert(!puneCreateError.message.includes("Pune"), "do not echo out-of-city internals");

  let outsidePreview = null;
  try {
    await previewSocietyFromPlace(
      mockPrisma([]),
      {
        placeId: "ChIJ-pune-preview",
        name: "Mantri Residency",
        city: "Pune",
        address: "Baner, Pune, Maharashtra, India",
      },
      { persist: false }
    );
  } catch (err) {
    outsidePreview = err;
  }
  assert(
    outsidePreview && outsidePreview.code === "LAUNCH_CITY_UNAVAILABLE",
    "preview of a Pune place does not create a society"
  );

  const blrCreate = mockPrisma([]);
  const createdBlr = await findOrCreateSocietyFromPlace(blrCreate, {
    placeId: "ChIJ-new-blr",
    name: "A Bengaluru Society",
    address: "Whitefield, Bengaluru, Karnataka, India",
    city: "Bangalore",
    state: "Karnataka",
    latitude: 12.97,
    longitude: 77.75,
  });
  assert(blrCreate._store.length === 1, "new Bengaluru society is created once");
  assert(createdBlr.city === "Bangalore" || createdBlr.city === "Bengaluru", "stores Google city");

  console.log("society-places tests passed");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
