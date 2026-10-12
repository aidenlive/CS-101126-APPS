#!/usr/bin/env node
// Rasterises the Brand Kit icon mark into the app's asset catalog:
// the iOS/iPadOS app icon (light, dark, tinted, 1024 px) and the macOS
// app icon (16–1024 px), plus the vector BrandMark image set.
//
// Source: internal/@csxbase/brand-kit/assets/logos/cardsite-icon-mark.svg.
// The mark is placed, not redrawn (Brand Kit → Logo → Misuse).
//
//   npm i --no-save @resvg/resvg-js@2.6.2
//   node platform/apps/apple/scripts/make-icons.mjs
//   python3 -c "from PIL import Image; p='platform/apps/apple/Cardsite/Resources/Assets.xcassets/AppIcon.appiconset/icon-ios-light.png'; Image.open(p).convert('RGB').save(p)"
//
// The last step matters: App Store Connect rejects a primary app icon that
// has an alpha channel, and resvg always writes RGBA.
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Resvg } from '@resvg/resvg-js';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '../../../..');
const markPath = join(repo, 'internal/@csxbase/brand-kit/assets/logos/cardsite-icon-mark.svg');
const assets = join(here, '../Cardsite/Resources/Assets.xcassets');

const markSvg = readFileSync(markPath, 'utf8');
// The drawable content of the mark (viewBox 0 0 158 158).
const inner = markSvg
  .replace(/<\?xml[^>]*>/, '')
  .replace(/<title>[^<]*<\/title>/, '')
  .replace(/^[\s\S]*?<svg[^>]*>/, '')
  .replace(/<\/svg>\s*$/, '');

// Studio tokens: bg (light) and bg (dark).
const LIGHT_BG = '#F7F8FA';
const DARK_BG = '#05060A';

function svg({ size, background, markScale, corner = 0, inset = 0, grayscale = false }) {
  const body = size - inset * 2;
  const markSize = body * markScale;
  const offset = inset + (body - markSize) / 2;
  const scale = markSize / 158;
  const filter = grayscale
    ? '<filter id="g"><feColorMatrix type="saturate" values="0"/><feComponentTransfer><feFuncR type="linear" slope="1.6"/><feFuncG type="linear" slope="1.6"/><feFuncB type="linear" slope="1.6"/></feComponentTransfer></filter>'
    : '';
  const bg = background
    ? `<rect x="${inset}" y="${inset}" width="${body}" height="${body}" rx="${corner}" ry="${corner}" fill="${background}"/>`
    : '';
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}"><defs>${filter}</defs>${bg}<g transform="translate(${offset} ${offset}) scale(${scale})"${grayscale ? ' filter="url(#g)"' : ''}>${inner}</g></svg>`;
}

function png(source, size) {
  return new Resvg(source, { fitTo: { mode: 'width', value: size } }).render().asPng();
}

function write(path, data) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, data);
}

// iOS / iPadOS: full-bleed square; the system applies the mask.
const ios = join(assets, 'AppIcon.appiconset');
write(join(ios, 'icon-ios-light.png'), png(svg({ size: 1024, background: LIGHT_BG, markScale: 0.62 }), 1024));
// Dark: Apple asks for a transparent background so the system can supply its own.
write(join(ios, 'icon-ios-dark.png'), png(svg({ size: 1024, background: null, markScale: 0.62 }), 1024));
write(join(ios, 'icon-ios-tinted.png'), png(svg({ size: 1024, background: null, markScale: 0.62, grayscale: true }), 1024));

// macOS: the icon draws its own rounded square inside the standard 824/1024 grid.
const macSizes = [16, 32, 128, 256, 512];
const macImages = [];
for (const base of macSizes) {
  for (const scale of [1, 2]) {
    const px = base * scale;
    const name = `icon-mac-${base}@${scale}x.png`;
    write(join(ios, name), png(svg({ size: 1024, background: LIGHT_BG, markScale: 0.6, inset: 100, corner: 185 }), px));
    macImages.push({ filename: name, idiom: 'mac', scale: `${scale}x`, size: `${base}x${base}` });
  }
}

write(join(ios, 'Contents.json'), JSON.stringify({
  images: [
    { filename: 'icon-ios-light.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
    { appearances: [{ appearance: 'luminosity', value: 'dark' }], filename: 'icon-ios-dark.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
    { appearances: [{ appearance: 'luminosity', value: 'tinted' }], filename: 'icon-ios-tinted.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
    ...macImages,
  ],
  info: { author: 'xcode', version: 1 },
}, null, 2) + '\n');

// Vector mark for in-app use.
const markSet = join(assets, 'BrandMark.imageset');
mkdirSync(markSet, { recursive: true });
copyFileSync(markPath, join(markSet, 'cardsite-icon-mark.svg'));
write(join(markSet, 'Contents.json'), JSON.stringify({
  images: [{ filename: 'cardsite-icon-mark.svg', idiom: 'universal' }],
  info: { author: 'xcode', version: 1 },
  properties: { 'preserves-vector-representation': true },
}, null, 2) + '\n');

// Accent colour = Studio accent-line (the AA-safe green for tinted controls).
write(join(assets, 'AccentColor.colorset/Contents.json'), JSON.stringify({
  colors: [
    { color: { 'color-space': 'srgb', components: { red: '0.008', green: '0.584', blue: '0.000', alpha: '1.000' } }, idiom: 'universal' },
    { appearances: [{ appearance: 'luminosity', value: 'dark' }], color: { 'color-space': 'srgb', components: { red: '0.259', green: '0.765', blue: '0.217', alpha: '1.000' } }, idiom: 'universal' },
  ],
  info: { author: 'xcode', version: 1 },
}, null, 2) + '\n');

write(join(assets, 'Contents.json'), JSON.stringify({ info: { author: 'xcode', version: 1 } }, null, 2) + '\n');

// A preview sheet for review (not shipped).
write(join(here, '../AppStore/icon-preview.png'), png(svg({ size: 1024, background: LIGHT_BG, markScale: 0.62, corner: 230 }), 512));
console.log('icons written to', assets);
