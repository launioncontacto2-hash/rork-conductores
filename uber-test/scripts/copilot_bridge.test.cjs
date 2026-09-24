const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..', '..');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260923170000_uber_test_dori_evaluation_bridge.sql'), 'utf8');
const edge = fs.readFileSync(path.join(root, 'supabase', 'functions', 'uber-test-copilot-evaluate', 'index.ts'), 'utf8');
const push = fs.readFileSync(path.join(root, 'supabase', 'functions', 'dori-copilot-push', 'index.ts'), 'utf8');
const deployWorkflow = fs.readFileSync(path.join(root, '.github', 'workflows', 'uber-test-backend-deploy.yml'), 'utf8');
const nextEdge = fs.readFileSync(path.join(root, 'supabase', 'functions', 'uber-test-next', 'index.ts'), 'utf8');
const resultEdge = fs.readFileSync(path.join(root, 'supabase', 'functions', 'uber-test-result', 'index.ts'), 'utf8');
const vehicleFixture = fs.readFileSync(path.join(root, 'scripts', 'provision-test-uber-dori-parameters.sql'), 'utf8');
const bridgeMigration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260923170000_uber_test_dori_evaluation_bridge.sql'), 'utf8');
const doriPushSwift = fs.readFileSync(path.join(root, 'ios-turno-ev', 'TurnoEV', 'ViewModels', 'DORICopilotInbox.swift'), 'utf8');
const appDelegateSwift = fs.readFileSync(path.join(root, 'ios-turno-ev', 'TurnoEV', 'Services', 'Acquisition', 'AcquisitionPushCoordinator.swift'), 'utf8');
const contentViewSwift = fs.readFileSync(path.join(root, 'ios-turno-ev', 'TurnoEV', 'ContentView.swift'), 'utf8');

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

test('presentation and outcomes invoke the evaluator with offer-scoped idempotency', () => {
  assert.match(nextEdge, /uber-test-copilot-evaluate/);
  assert.match(nextEdge, /uber-test-offer-\$\{presented\.offer\.id\}/);
  assert.match(resultEdge, /next_offer_id/);
  assert.match(resultEdge, /uber-test-offer-\$\{nextOfferId\}/);
  assert.match(bridgeMigration, /next_offer_id/);
  assert.match(bridgeMigration, /not exists\(select 1 from public\.uber_test_offer_results/);
});

test('context resolution preserves caller identity and TEST parameters are provisioned explicitly', () => {
  assert.match(edge, /caller\.rpc\("resolve_uber_test_dori_context"/);
  assert.match(vehicleFixture, /uber-test-v1/);
  assert.match(vehicleFixture, /where e\.code = 'test'/);
});

test('DORI app receives the shared APNs token without a competing app delegate', () => {
  assert.match(doriPushSwift, /class DORICopilotPushCoordinator/);
  assert.match(doriPushSwift, /register_dori_copilot_push_device/);
  assert.match(appDelegateSwift, /DORICopilotPushCoordinator\.shared\.receivedDeviceToken/);
  assert.match(appDelegateSwift, /DORICopilotPushCoordinator\.shared\.receivedNotification/);
});

test('Copilot TEST lifecycle is gated by an active shift', () => {
  assert.match(contentViewSwift, /store\.activeShift\s*!=\s*nil/);
  assert.match(contentViewSwift, /store\.activeShift\?\.id/);
});
