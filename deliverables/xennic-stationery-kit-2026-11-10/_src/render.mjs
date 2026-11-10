// Rasterise the temporary preview SVGs (written by build_svg.py) into ../png
// usage:  python3 make.py && node render.mjs      (needs: npm i sharp)
import sharp from 'sharp';
import fs from 'fs';
import path from 'path';

const srcDir = '/tmp';
const outDir = path.resolve('../png');
const TARGET_LONG = 2000;      // px on the long edge of every preview

const files = fs.readdirSync(srcDir).filter(f => f.endsWith('.preview.svg')).sort();
for (const f of files) {
  const src = path.join(srcDir, f);
  // pass 1 — measure at 96 dpi (1 mm = 3.7795 px)
  const meta = await sharp(src, { density: 96 }).metadata();
  const baseLong = Math.max(meta.width, meta.height);
  const density = Math.min(1200, Math.ceil((96 * TARGET_LONG) / baseLong));
  const out = path.join(outDir, f.replace('.preview.svg', '.png'));
  // pass 2 — render natively at that resolution, then trim to the exact size
  await sharp(src, { density })
    .resize({ width: Math.round((meta.width * TARGET_LONG) / baseLong), kernel: 'lanczos3' })
    .png({ compressionLevel: 9 })
    .toFile(out);
  const info = await sharp(out).metadata();
  console.log(path.basename(out).padEnd(34), (info.width + 'x' + info.height).padEnd(11),
              (fs.statSync(out).size / 1024).toFixed(0) + ' KB', ' dpi=' + density);
}
