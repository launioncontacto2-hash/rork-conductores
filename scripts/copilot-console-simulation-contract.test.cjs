'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { scenario } = require('./copilot-fixtures.cjs');
const { createSimulationCase, toEngineInput, evaluateSimulation } = require('./copilot-console-simulation-contract.cjs');
const fs = require('node:fs');
const path = require('node:path');

const makeCase = (expected, overrides = {}) => createSimulationCase({
  testCaseId: overrides.testCaseId ?? 'case-001',
  createdAt: '2026-09-07T10:00:01-06:00',
  expiresAt: overrides.expiresAt ?? '2026-09-07T10:01:00-06:00',
  driverProfileId: 'simulated-driver-profile',
  stationId: 'station-001',
  input: overrides.input ?? scenario('A'),
  expected: { recommendation: expected, actorProfileId: 'console-actor', criterionVersion: 'lab-1.0.0' },
});

test('expected recomendado + actual recomendado clasifica correct_recommend', () => {
  const result = evaluateSimulation(makeCase('RECOMENDADO'));
  assert.equal(result.classification, 'correct_recommend');
  assert.equal(result.match, true);
});

test('expected rechazo + actual rechazo clasifica correct_reject', () => {
  const result = evaluateSimulation(makeCase('NO RECOMENDADO', { input: scenario('D') }));
  assert.equal(result.classification, 'correct_reject');
});

test('false positive y false negative se distinguen', () => {
  assert.equal(evaluateSimulation(makeCase('RECOMENDADO', { input: scenario('D') })).classification, 'false_negative');
  assert.equal(evaluateSimulation(makeCase('NO RECOMENDADO', { input: scenario('A') })).classification, 'false_positive');
});

test('expected queda fuera del input entregado al motor', () => {
  const simulation = makeCase('RECOMENDADO');
  const input = toEngineInput(simulation);
  assert.equal(input.expected, undefined);
  assert.equal(input.source, 'simulated');
  assert.equal(simulation.source, 'console_simulation');
});

test('la simulación está marcada y nunca se confunde con live', () => {
  const simulation = makeCase('RECOMENDADO');
  assert.equal(simulation.isSimulation, true);
  assert.equal(simulation.source, 'console_simulation');
  assert.throws(() => createSimulationCase({ ...simulation, input: { ...simulation.input, source: 'manual' }, expected: simulation.expected }), /simulated_source/);
});

test('preserva versiones, máximo tres razones y evaluación determinista', () => {
  const simulation = makeCase('RECOMENDADO');
  const first = evaluateSimulation(simulation);
  const second = evaluateSimulation(simulation);
  assert.deepEqual(first, second);
  assert.deepEqual(first.versions, { modelVersion: 'deterministic-0.1', rulesVersion: '0.1.0', parameterVersion: 'mxn-lab-0.1.0' });
  assert.ok(first.actual.reasons.length >= 1 && first.actual.reasons.length <= 3);
});

test('caso expirado se rechaza antes de ejecutar el motor', () => {
  const simulation = makeCase('RECOMENDADO', { expiresAt: '2026-09-07T10:00:30-06:00' });
  assert.throws(() => evaluateSimulation(simulation, '2026-09-07T10:00:31-06:00'), /simulation_expired/);
});

test('contrato remoto expone CORS, estado y result_payload', () => {
  const edge = fs.readFileSync(path.join(__dirname, '..', 'supabase/functions/dori-copilot-simulation/index.ts'), 'utf8');
  assert.match(edge, /authorization, x-client-info, apikey, content-type/);
  assert.match(edge, /result_payload/);
  const migration = fs.readFileSync(path.join(__dirname, '..', 'supabase/migrations/20260922103000_dori_copilot_simulation_contract.sql'), 'utf8');
  assert.match(migration, /'status',c\.status/);
});
