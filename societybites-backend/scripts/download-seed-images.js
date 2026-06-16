/**
 * Downloads Wikimedia Commons photos for seed listings.
 * Run: npm run download-seed-images
 */
const fs = require("fs");
const path = require("path");
const https = require("https");

const OUT_DIR = path.join(__dirname, "..", "seed-images");

const IMAGES = {
  "dal-makhani.jpg":
    "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3e/Dal_Makhani..JPG/960px-Dal_Makhani..JPG",
  "chapati.jpg":
    "https://upload.wikimedia.org/wikipedia/commons/thumb/5/5b/Chapati.jpg/960px-Chapati.jpg",
  "chicken-biryani.jpg":
    "https://upload.wikimedia.org/wikipedia/commons/d/d1/Hyderabadi_Biryani.jpg",
  "paneer-butter-masala.jpg":
    "https://upload.wikimedia.org/wikipedia/commons/0/04/Butter_Paneer_%2C_Butter_Naan_%2C_PK_017.jpg",
  "lemon-rice.jpg":
    "https://upload.wikimedia.org/wikipedia/commons/c/cb/Lime_rice.jpg",
};

function download(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    https
      .get(
        url,
        {
          headers: {
            "User-Agent": "SocietyBites-Seed/1.0",
            Accept: "image/*",
          },
        },
        (res) => {
          if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
            file.close();
            fs.unlinkSync(dest);
            return download(res.headers.location, dest).then(resolve).catch(reject);
          }
          if (res.statusCode !== 200) {
            file.close();
            fs.unlinkSync(dest);
            return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
          }
          res.pipe(file);
          file.on("finish", () => file.close(() => resolve(dest)));
        }
      )
      .on("error", (err) => {
        file.close();
        fs.unlink(dest, () => reject(err));
      });
  });
}

async function main() {
  fs.mkdirSync(OUT_DIR, { recursive: true });

  for (const [filename, url] of Object.entries(IMAGES)) {
    const dest = path.join(OUT_DIR, filename);
    process.stdout.write(`Downloading ${filename}... `);
    await download(url, dest);
    const size = fs.statSync(dest).size;
    console.log(`${(size / 1024).toFixed(1)} KB`);
  }

  console.log("Done.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
