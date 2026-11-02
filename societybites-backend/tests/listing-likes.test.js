const { dishKeyFor, applyListingLikes } = require("../lib/listingLikes");

function assert(cond, message) {
  if (!cond) throw new Error(message);
}

const small = { id: "size-250", variantGroupId: "dish-a" };
const large = { id: "size-500", variantGroupId: "dish-a" };
const solo = { id: "solo-1", variantGroupId: null };

assert(dishKeyFor(small) === "dish-a", "sizes share the dish key");
assert(dishKeyFor(large) === dishKeyFor(small), "both sizes use one key");
assert(dishKeyFor(solo) === "solo-1", "a dish without sizes uses its listing id");
assert(dishKeyFor({ id: "x", variantGroupId: "  " }) === "x", "blank group falls back to id");

const listings = [
  { id: "size-250", variantGroupId: "dish-a" },
  { id: "size-500", variantGroupId: "dish-a" },
  { id: "solo-1", variantGroupId: null },
];
applyListingLikes(listings, {
  counts: new Map([
    ["dish-a", 12],
    ["solo-1", 0],
  ]),
  likedKeys: new Set(["dish-a"]),
});

assert(listings[0].likeCount === 12 && listings[1].likeCount === 12, "both sizes show the same count");
assert(listings[0].likedByMe === true && listings[1].likedByMe === true, "one like covers both sizes");
assert(listings[2].likeCount === 0 && listings[2].likedByMe === false, "unliked dish stays at zero");

console.log("listing likes ok");
