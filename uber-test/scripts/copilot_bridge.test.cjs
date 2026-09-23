const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..', '..');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260923170000_uber_test_dori_evaluation_bridge.sql'), 'utf8');
const edge = fs.readFileSync(path.join(root, 'supabase', 'functions', 'uber-test-copilot-evaluate', 'index.ts'), 'utf8');
const push = fs.readFileSync(path.join(root, 'supabase', 'functions', 'dori-copilot-push', 'index.ts'), 'utf8');
const deployWorkflow = fs.readFileSync(path.join(root, '.github', 'workflows', 'uber-test-backend-deploy.yml'), 'utf8');

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

test('DORI push dispatcher is isolated from Acquisition and deduplicates by offer', () => {
  assert.match(push, /claim_dori_copilot_notifications/);
  assert.match(push, /dori_copilot_push_devices/);
  assert.match(push, /offerId:n\.offer_id/);
  assert.match(push, /turno:\/\/copiloto/);
  assert.doesNotMatch(push, /acquisition_notifications/);
});

test('TEST deployment workflow includes the evaluation and push functions', () => {
  assert.match(deployWorkflow, /feat\/copilot-uber-test-bridge/);
  assert.match(deployWorkflow, /supabase functions deploy uber-test-copilot-evaluate/);
  assert.match(deployWorkflow, /supabase functions deploy dori-copilot-push/);
  assert.match(deployWorkflow, /yyxzuiantrmoyozetswv/);
});
