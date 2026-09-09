'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const catalogDirectory = path.resolve(
  __dirname,
  '../ios-turno-ev/TurnoEV/Assets.xcassets/AppIcon.appiconset',
);
const catalog = JSON.parse(
  fs.readFileSync(path.join(catalogDirectory, 'Contents.json'), 'utf8'),
);
const distributionIcon = catalog.images.find(
  (image) => image.platform === 'ios' && image.idiom === 'universal' && image.size === '1024x1024',
);

assert.ok(distributionIcon?.filename, 'AppIcon must declare a universal 1024x1024 iOS image');
assert.equal(path.extname(distributionIcon.filename).toLowerCase(), '.png', 'AppIcon must be a PNG');

const icon = fs.readFileSync(path.join(catalogDirectory, distributionIcon.filename));
assert.ok(icon.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])), 'AppIcon is not a valid PNG');
assert.equal(icon.subarray(12, 16).toString('ascii'), 'IHDR', 'AppIcon PNG has no IHDR header');

const width = icon.readUInt32BE(16);
const height = icon.readUInt32BE(20);
const bitDepth = icon[24];
const colorType = icon[25];
const hasTransparencyChunk = icon.includes(Buffer.from('tRNS'));

assert.equal(width, 1024, 'AppIcon width must be exactly 1024 pixels');
assert.equal(height, 1024, 'AppIcon height must be exactly 1024 pixels');
assert.equal(bitDepth, 8, 'AppIcon must use 8 bits per channel');
assert.equal(colorType, 2, 'AppIcon must be truecolor RGB without an alpha channel');
assert.equal(hasTransparencyChunk, false, 'AppIcon must not contain PNG transparency');

console.log(`AppIcon valido: ${distributionIcon.filename} | ${width}x${height} | PNG RGB | sin alpha`);
