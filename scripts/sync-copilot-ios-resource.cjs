#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const canonicalPath = path.join(root, 'supabase', 'functions', '_shared', 'dori-copilot.js');
const iosPath = path.join(root, 'ios-turno-ev', 'TurnoEV', 'Resources', 'dori-copilot.js');
const canonical = fs.readFileSync(canonicalPath);

if (process.argv.includes('--check')) {
  const ios = fs.existsSync(iosPath) ? fs.readFileSync(iosPath) : Buffer.alloc(0);
  if (!canonical.equals(ios)) {
    console.error('El recurso iOS no corresponde al motor canonico. Ejecuta: node scripts/sync-copilot-ios-resource.cjs');
    process.exit(1);
  }
  console.log('Recurso iOS sincronizado con el motor canonico.');
  process.exit(0);
}

fs.mkdirSync(path.dirname(iosPath), { recursive: true });
fs.writeFileSync(iosPath, canonical);
console.log(`Recurso iOS generado desde ${path.relative(root, canonicalPath)}.`);
