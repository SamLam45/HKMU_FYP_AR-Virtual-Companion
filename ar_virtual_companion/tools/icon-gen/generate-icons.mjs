import fs from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const repoRoot = path.resolve(import.meta.dirname, "..", "..");
const svgPath = path.join(repoRoot, "assets", "app_icon.svg");

async function ensureDir(p) {
  await fs.mkdir(p, { recursive: true });
}

async function renderPng({ size, outPath }) {
  // Use a solid background so launcher icons aren't transparent on Android.
  const png = await sharp(svgPath, { density: 384 })
    .resize(size, size, { fit: "cover" })
    .flatten({ background: "#ffffff" })
    .png()
    .toBuffer();

  await fs.writeFile(outPath, png);
}

async function main() {
  // iOS AppIcon filenames are dictated by Contents.json already in the repo.
  const iosOutDir = path.join(
    repoRoot,
    "ios",
    "Runner",
    "Assets.xcassets",
    "AppIcon.appiconset"
  );
  await ensureDir(iosOutDir);

  const iosFiles = [
    ["Icon-App-20x20@1x.png", 20],
    ["Icon-App-20x20@2x.png", 40],
    ["Icon-App-20x20@3x.png", 60],
    ["Icon-App-29x29@1x.png", 29],
    ["Icon-App-29x29@2x.png", 58],
    ["Icon-App-29x29@3x.png", 87],
    ["Icon-App-40x40@1x.png", 40],
    ["Icon-App-40x40@2x.png", 80],
    ["Icon-App-40x40@3x.png", 120],
    ["Icon-App-60x60@2x.png", 120],
    ["Icon-App-60x60@3x.png", 180],
    ["Icon-App-76x76@1x.png", 76],
    ["Icon-App-76x76@2x.png", 152],
    ["Icon-App-83.5x83.5@2x.png", 167],
    ["Icon-App-1024x1024@1x.png", 1024]
  ];

  for (const [name, size] of iosFiles) {
    await renderPng({ size, outPath: path.join(iosOutDir, name) });
  }

  // Android launcher icons (PNG mipmaps).
  const androidResDir = path.join(repoRoot, "android", "app", "src", "main", "res");
  const androidMipmaps = [
    ["mipmap-mdpi", 48],
    ["mipmap-hdpi", 72],
    ["mipmap-xhdpi", 96],
    ["mipmap-xxhdpi", 144],
    ["mipmap-xxxhdpi", 192]
  ];

  for (const [dir, size] of androidMipmaps) {
    const outDir = path.join(androidResDir, dir);
    await ensureDir(outDir);
    await renderPng({ size, outPath: path.join(outDir, "ic_launcher.png") });
    await renderPng({ size, outPath: path.join(outDir, "ic_launcher_round.png") });
  }

  console.log("Done. Generated iOS + Android launcher icon PNGs.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

