const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const canonicalPath = path.join(root, 'supabase/functions/_shared/dori-copilot.js');
const iosPath = path.join(root, 'ios-turno-ev/TurnoEV/Resources/dori-copilot.js');

test('the iOS JavaScriptCore resource is byte-identical to the canonical engine', () => {
  assert.deepEqual(fs.readFileSync(iosPath), fs.readFileSync(canonicalPath));
});

test('the synchronized resource boots without CommonJS and exposes evaluateJSON', () => {
  const context = vm.createContext({});
  vm.runInContext(fs.readFileSync(iosPath, 'utf8'), context);
  assert.equal(typeof context.DoriCopilot.evaluateJSON, 'function');
});
