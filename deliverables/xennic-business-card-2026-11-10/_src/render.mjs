// Rasterise the card previews to ../png   (usage: python3 build_card.py && python3 presentation.py && node render.mjs)
import sharp from 'sharp';
import fs from 'fs';
import path from 'path';

const outDir = path.resolve('../png');
const jobs = [
  ['/tmp/xennic-business-card-front.preview.svg', 'xennic-business-card-front.png', 2000],
  ['/tmp/xennic-business-card-back.preview.svg',  'xennic-business-card-back.png',  2000],
  ['/tmp/card-pair.preview.svg',                  'xennic-business-card-pair.png',  2200],
];
for (const [src, name, w] of jobs) {
  const meta = await sharp(src, { density: 96 }).metadata();
  const density = Math.min(1200, Math.ceil((96 * w) / meta.width));
  const pipe = sharp(src, { density }).resize({ width: w, kernel: 'lanczos3' });
  await pipe.png({ compressionLevel: 9 }).toFile(path.join(outDir, name));
  const info = await sharp(path.join(outDir, name)).metadata();
  console.log(name.padEnd(38), (info.width + 'x' + info.height).padEnd(11),
    (fs.statSync(path.join(outDir, name)).size / 1024).toFixed(0) + ' KB');
}
