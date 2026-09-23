const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..', '..');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260923170000_uber_test_dori_evaluation_bridge.sql'), 'utf8');
const edge = fs.readFileSync(path.join(root, 'supabase', 'functions', 'uber-test-copilot-evaluate', 'index.ts'), 'utf8');

test('Uber Test bridge carries pickup and TEST destination context', () => {
  assert.match(migration, /pickup_minutes/);
  assert.match(migration, /destination_to_station_km/);
  assert.match(migration, /destination_value/);
  assert.match(migration, /dori_copilot_test_vehicle_parameters/);
  assert.match(migration, /status','no_active_shift/);
  assert.match(migration, /demand','automatic/);
  assert.match(migration, /driverId',d\.profile_id/);
});

test('Uber Test evaluation executes canonical engine and links offer id', () => {
  assert.match(edge, /doriCopilot\.createDecisionEvent/);
  assert.match(edge, /offerId: body\.offerId/);
  assert.match(edge, /record_dori_decision_event/);
  assert.match(edge, /copilot_status: "evaluated"/);
  assert.doesNotMatch(edge, /acquisition_notifications/);
});
