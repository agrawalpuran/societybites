const fs = require("fs");
const path = require("path");

const SEED_DIR = path.join(__dirname, "..", "seed-images");
const UPLOADS_DIR = path.join(__dirname, "..", "uploads");

/** Copy seed photos into uploads/ (overwrite when source is newer). */
function setupSeedImages({ force = false } = {}) {
  fs.mkdirSync(UPLOADS_DIR, { recursive: true });

  if (!fs.existsSync(SEED_DIR)) {
    console.warn("seed-images folder not found — skipping seed image copy");
    return 0;
  }

  let copied = 0;
  for (const file of fs.readdirSync(SEED_DIR)) {
    if (!file.endsWith(".jpg")) continue;

    const src = path.join(SEED_DIR, file);
    const dest = path.join(UPLOADS_DIR, file);
    const shouldCopy =
      force ||
      !fs.existsSync(dest) ||
      fs.statSync(src).mtimeMs > fs.statSync(dest).mtimeMs;

    if (shouldCopy) {
      fs.copyFileSync(src, dest);
      copied++;
    }
  }

  if (copied > 0) {
    console.log(`Synced ${copied} seed image(s) to uploads/`);
  }

  return copied;
}

module.exports = { setupSeedImages, UPLOADS_DIR, SEED_DIR };
