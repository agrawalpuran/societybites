const sharp = require("sharp");
const { optimizeListingPhoto, MAX_EDGE } = require("../lib/listingImageOptimize");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function main() {
  const large = await sharp({
    create: {
      width: 2400,
      height: 1600,
      channels: 3,
      background: { r: 220, g: 120, b: 40 },
    },
  })
    .jpeg()
    .toBuffer();

  const optimized = await optimizeListingPhoto(large);
  assert(optimized.mimeType === "image/jpeg", "large listing becomes jpeg");
  const meta = await sharp(optimized.buffer).metadata();
  assert(meta.width <= MAX_EDGE && meta.height <= MAX_EDGE, "fits within max edge");
  assert(meta.width === MAX_EDGE, "width capped at max edge");
  assert(optimized.buffer.length < large.length, "smaller than original");

  const small = await sharp({
    create: { width: 400, height: 300, channels: 3, background: "#88cc88" },
  })
    .jpeg()
    .toBuffer();
  const smallOut = await optimizeListingPhoto(small);
  const smallMeta = await sharp(smallOut.buffer).metadata();
  assert(smallMeta.width === 400 && smallMeta.height === 300, "does not enlarge");

  try {
    await optimizeListingPhoto(Buffer.from("not an image"));
    throw new Error("garbage should fail");
  } catch (err) {
    if (err.message === "garbage should fail") throw err;
    assert(err.statusCode === 400, "invalid image is 400");
  }

  console.log("listing-image-optimize ok");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
