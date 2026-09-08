'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const engine = require('../ios-turno-ev/TurnoEV/Resources/dori-copilot.js');
const { scenario } = require('./copilot-fixtures.cjs');
const simulator = require('./copilot-simulator.cjs');

const clone = value => JSON.parse(JSON.stringify(value));

test('simulator delegates individual decisions to the exact V0.1 engine', () => {
  const input = simulator.applyVariables(scenario('A'), {
    hour: 18, demand: 'high', battery: 30, remaining: 120,
    pickup: 6, fare: 180, distance: 12, destinationValue: 65
  });
  const direct = engine.evaluate(input);
  const originalEvaluate = engine.evaluate;
  let calls = 0;
  engine.evaluate = value => { calls += 1; return originalEvaluate(value); };
  try {
    assert.deepEqual(simulator.evaluateInput(input).result, direct);
    assert.equal(calls, 1);
  } finally {
    engine.evaluate = originalEvaluate;
  }
});

test('individual execution varies every requested dimension without mutating fixtures', () => {
  const original = scenario('A');
  const run = simulator.runIndividual({ fixture: 'A', variables: {
    hour: 22, demand: 'low', battery: 30, remaining: 120,
    pickup: 35, fare: 450, distance: 40, destinationValue: 20
  }});
  assert.equal(run.input.market.hour, 22);
  assert.equal(run.input.market.demand, 'low');
  assert.equal(run.input.vehicle.batteryPercent, 30);
  assert.equal(run.input.driver.remainingMinutes, 120);
  assert.equal(run.input.trip.pickupMinutes, 35);
  assert.equal(run.input.trip.fare, 450);
  assert.equal(run.input.trip.tripKm, 40);
  assert.equal(run.input.market.destinationValue, 20);
  assert.deepEqual(scenario('A'), original);
  assert.throws(() => simulator.runIndividual({ fixture: 'unknown' }), /invalid_fixture/);
});

test('hour sweep executes the same offer at 05, 07, 10, 14, 18, 22 and 01', () => {
  const sweep = simulator.runHourlySweep(scenario('C'));
  assert.deepEqual(sweep.map(item => item.input.market.hour), [5, 7, 10, 14, 18, 22, 1]);
  assert.deepEqual(sweep.map(item => item.result.demand), ['low', 'high', 'normal', 'normal', 'high', 'low', 'low']);
  const tripShape = ({ timestamp, ...trip }) => trip;
  for (const item of sweep) assert.deepEqual(tripShape(item.input.trip), tripShape(sweep[0].input.trip));
});

test('the same trip changes coherently across low, normal and high demand', () => {
  const base = scenario('C');
  const results = ['low', 'normal', 'high'].map(demand =>
    simulator.evaluateInput(simulator.applyVariables(base, { demand })).result
  );
  assert.deepEqual(results.map(result => result.threshold), [58, 65, 70]);
  assert.ok(results[0].expectedRejectValue < results[1].expectedRejectValue);
  assert.ok(results[1].expectedRejectValue < results[2].expectedRejectValue);
  assert.equal(results[0].recommendation, 'RECOMENDADO');
  assert.equal(results[2].recommendation, 'NO RECOMENDADO');
});

test('sufficient and insufficient battery exercise the operational veto', () => {
  const sufficient = simulator.runIndividual({ variables: { battery: 80 } }).result;
  const insufficient = simulator.runIndividual({ variables: { battery: 5 } }).result;
  assert.equal(sufficient.operationalBlocks.includes('Batería insuficiente'), false);
  assert.equal(insufficient.recommendation, 'NO RECOMENDADO');
  assert.ok(insufficient.operationalBlocks.includes('Batería insuficiente'));
});

test('exact shift start is valid and the end-of-shift margin blocks an infeasible trip', () => {
  const atStart = simulator.applyVariables(scenario('A'), { hour: 10, remaining: 480 });
  atStart.driver.shiftStart = atStart.market.now;
  assert.equal(engine.evaluate(atStart).operationalBlocks.includes('El turno aún no comienza'), false);

  const atEnd = simulator.applyVariables(scenario('A'), { hour: 10, remaining: 20 });
  assert.equal(engine.evaluate(atEnd).recommendation, 'NO RECOMENDADO');
  assert.ok(engine.evaluate(atEnd).operationalBlocks.includes('No permite regresar a tiempo'));
});

test('short and excessive pickup cannot hide behind the fare', () => {
  const short = simulator.runIndividual({ fixture: 'A', variables: { pickup: 2 } }).result;
  const excessive = simulator.runIndividual({ fixture: 'B', variables: { pickup: 95 } }).result;
  assert.ok(short.scores.pickup > excessive.scores.pickup);
  assert.equal(excessive.recommendation, 'NO RECOMENDADO');
  assert.ok(excessive.reasons.includes('Mucho tiempo para recoger'));
});

test('near-threshold decisions are retained with a complete diagnostic snapshot', () => {
  const run = simulator.runIndividual({ fixture: 'D' });
  assert.equal(run.result.nearBoundary, true);
  const report = simulator.inspectResult(run.input, { ...run.result, opportunityCost: 999 })[0];
  assert.deepEqual(Object.keys(report), [
    'type', 'message', 'input', 'recommendation', 'score', 'threshold',
    'expectedAcceptValue', 'expectedRejectValue', 'opportunityCost',
    'operationalBlocks', 'reasons'
  ]);
  assert.equal(report.type, 'opportunity_cost_mismatch');
});

test('both baseline policies are evaluated and the hourly minimum is configurable', () => {
  const input = simulator.applyVariables(scenario('C'), { demand: 'normal' });
  const permissive = simulator.evaluateInput(input, { minimumNetHourly: 1 });
  const strict = simulator.evaluateInput(input, { minimumNetHourly: 1000 });
  assert.equal(permissive.baselines.acceptAll, true);
  assert.equal(strict.baselines.acceptAll, true);
  assert.equal(permissive.baselines.minimumNetConnectedHourly, true);
  assert.equal(strict.baselines.minimumNetConnectedHourly, false);
});

test('small Cartesian grids are deterministic and include anomaly diagnostics', () => {
  const grid = {
    hours: [5, 18], demands: ['low', 'high'], batteries: [5, 80],
    remainingMinutes: [20, 360], pickupMinutes: [2, 35], fares: [60, 240],
    tripKm: [3, 40], destinationValues: [20, 95]
  };
  const first = simulator.runMassSimulation({ grid, minimumNetHourly: 150 });
  const second = simulator.runMassSimulation({ grid: clone(grid), minimumNetHourly: 150 });
  assert.deepEqual(first, second);
  assert.equal(first.scenarioCount, 256);
  assert.equal(first.metamorphicChecks, 1024);
  assert.equal(first.anomalyCount, 0);
  for (const strategy of Object.values(first.strategies)) {
    assert.equal(strategy.accepted + strategy.rejected, first.scenarioCount);
  }
});

test('default adversarial matrix covers all dimensions without contradictions', { timeout: 30000 }, () => {
  const report = simulator.runMassSimulation();
  assert.equal(report.scenarioCount, 13608);
  assert.equal(report.metamorphicChecks, 54432);
  assert.equal(report.anomalyCount, 0);
  assert.ok(report.nearBoundaryCount > 0);
  assert.ok(report.boundarySamples.length > 0);
  assert.equal(report.strategies.acceptAll.accepted, report.scenarioCount);
  assert.ok(report.strategies.acceptAll.operationallyBlockedAcceptances > 0);
  assert.equal(report.strategies.dori.operationallyBlockedAcceptances, 0);
});
