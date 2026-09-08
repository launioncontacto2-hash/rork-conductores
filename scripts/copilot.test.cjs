const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const engine = require('../supabase/functions/_shared/dori-copilot.js');
const { scenario } = require('./copilot-fixtures.cjs');
const clone = x => JSON.parse(JSON.stringify(x));

test('A-E: economics, opportunity and operational vetoes', () => {
  for (const [name, expected] of Object.entries({ A:'RECOMENDADO', B:'NO RECOMENDADO', C:'RECOMENDADO', D:'NO RECOMENDADO', E:'NO RECOMENDADO' })) {
    const result=engine.evaluate(scenario(name));
    assert.equal(result.recommendation, expected, name);
    assert.ok(result.reasons.length>=1 && result.reasons.length<=3);
    assert.ok(result.reasons.every(reason=>!/(score|confidence|threshold|machine learning)/i.test(reason)));
  }
  assert.deepEqual(scenario('C').trip, scenario('D').trip);
  assert.ok(engine.evaluate(scenario('E')).operationalBlocks.length >= 2);
});

test('pure engine, full replay and global entry without Node dependencies', () => {
  assert.equal(require('../ios-turno-ev/TurnoEV/Resources/dori-copilot.js'), engine);
  const input = scenario('A'), original = clone(input);
  const r = engine.evaluate(input);
  assert.deepEqual(engine.evaluate(input, r.parameters), r);
  assert.deepEqual(input, original);
  const context = vm.createContext({});
  vm.runInContext(fs.readFileSync(require.resolve('../supabase/functions/_shared/dori-copilot.js'), 'utf8'), context);
  assert.deepEqual(JSON.parse(context.DoriCopilot.evaluateJSON(JSON.stringify(input))), r);
});

test('invalid, non-finite, stale and unknown demand never produce a recommendation', () => {
  for (const value of [-1, NaN, Infinity, '240', null]) {
    const i=scenario('A'); i.trip.fare=value; assert.throws(() => engine.evaluate(i));
  }
  for (const change of [i=>i.market.demand='unknown',i=>i.vehicle.batteryPercent=101,
    i=>i.trip.tripMinutes=0,i=>i.trip.timestamp='2020-01-01T00:00:00Z',i=>i.driver.shiftEnd=i.driver.shiftStart]) {
    const i=scenario('A'); change(i); assert.throws(()=>engine.evaluate(i));
  }
  const p=engine.defaultParameters(); p.weights.time=0.9; assert.throws(()=>engine.evaluate(scenario('A'),p));
});

test('exact operational boundaries include safe return and reserve', () => {
  const i=scenario('A'), p=engine.defaultParameters();
  i.vehicle.rangeKm=i.trip.pickupKm+i.trip.tripKm+i.vehicle.destinationToStationKm+p.rangeReserveKm;
  assert.equal(engine.evaluate(i).operationalBlocks.length,0);
  i.vehicle.rangeKm-=0.001; assert.ok(engine.evaluate(i).operationalBlocks.length);
  i.vehicle.rangeKm=200; i.vehicle.batteryPercent=p.batteryReservePercent;
  assert.equal(engine.evaluate(i).recommendation,'NO RECOMENDADO');
  i.vehicle.batteryPercent=80; i.driver.remainingMinutes=26+8/25*60+10;
  assert.equal(engine.evaluate(i).operationalBlocks.length,0);
  i.driver.remainingMinutes-=0.001; assert.equal(engine.evaluate(i).recommendation,'NO RECOMENDADO');
});

test('threshold equality and tiny perturbation are flagged for later analysis', () => {
  const i=scenario('A'), p=engine.defaultParameters();
  p.parameterVersion='boundary-test-1'; p.thresholds.high=100;
  p.thresholds.normal=engine.evaluate(i,p).total;
  assert.equal(engine.evaluate(i,p).recommendation,'RECOMENDADO');
  assert.equal(engine.evaluate(i,p).nearBoundary,true);
  p.thresholds.normal+=0.00001;
  assert.equal(engine.evaluate(i,p).recommendation,'NO RECOMENDADO');
  assert.equal(engine.evaluate(i,p).nearBoundary,true);
});

test('all four named contracts validate independently and reject missing fields', () => {
  const i=scenario('A');
  for (const [name, value] of [['TripCandidate',i.trip],['MarketContext',i.market],['VehicleContext',i.vehicle],['DriverContext',i.driver]]) {
    const validator=engine['validate'+name];
    assert.doesNotThrow(()=>validator(value),name);
    for(const key of Object.keys(value)) {
      const incomplete=clone(value); delete incomplete[key];
      assert.throws(()=>validator(incomplete),name+'.'+key);
    }
  }
});

test('versions, weights and thresholds are explicit and overrides are auditable', () => {
  const p=engine.defaultParameters();
  assert.deepEqual(p.weights,{time:0.35,distance:0.20,pickup:0.15,destination:0.20,operational:0.10});
  assert.deepEqual(p.thresholds,{low:58,normal:65,high:70});
  p.thresholds.low=50;
  assert.throws(()=>engine.evaluate(scenario('A'),p),/new_version/);
  p.parameterVersion='calibration-test-1';
  assert.equal(engine.evaluate(scenario('A'),p).parameterVersion,'calibration-test-1');
  p.weights={time:1,distance:0,pickup:0,destination:0,operational:0};
  const override=engine.evaluate(scenario('C'),p);
  assert.equal(override.total,override.scores.time);
  p.modelVersion='learned-fiction'; assert.throws(()=>engine.evaluate(scenario('A'),p),/unsupported_engine/);
  assert.equal(engine.defaultParameters().thresholds.low,58);
  const sparse=engine.defaultParameters(); sparse.parameterVersion='invalid-sparse-1'; sparse.hourlyDemand=Array(24);
  assert.throws(()=>engine.evaluate(scenario('A'),sparse));
});

test('connected economics includes pickup, wait, repositioning, energy and wear', () => {
  const input=scenario('A'), r=engine.evaluate(input), p=engine.defaultParameters();
  const net=240-12*(0.6+p.wearCostPerKm), minutes=4+22+8+3;
  assert.equal(r.expectedAcceptValue,net);
  assert.equal(r.connectedMinutes,minutes);
  assert.equal(r.netConnectedHourly,net*60/minutes);
  assert.equal(r.expectedRejectValue,p.alternativeNetHourly.normal*minutes/60);
  assert.equal(r.opportunityCost,r.expectedRejectValue-r.expectedAcceptValue);
  assert.equal(r.total,Object.keys(p.weights).reduce((sum,k)=>sum+p.weights[k]*r.scores[k],0));
  input.market.nextWaitMinutes+=10;
  assert.ok(engine.evaluate(input).netConnectedHourly<r.netConnectedHourly);
  input.trip.fare+=100;
  assert.ok(engine.evaluate(input).expectedAcceptValue>r.expectedAcceptValue);
});

test('opportunity cost preserves the signed reject-minus-accept difference', () => {
  const favorableAccept=engine.evaluate(scenario('A'));
  const favorableReject=engine.evaluate(scenario('D'));
  assert.ok(favorableAccept.opportunityCost<0);
  assert.ok(favorableReject.opportunityCost>0);

  const equivalent=scenario('A');
  const parameters=engine.defaultParameters();
  parameters.parameterVersion='opportunity-cost-equivalence-test-1';
  Object.assign(equivalent.trip,{fare:120,pickupMinutes:0,pickupKm:0,tripMinutes:30,tripKm:0});
  Object.assign(equivalent.market,{nextWaitMinutes:30,repositionMinutes:0,repositionKm:0});
  parameters.alternativeNetHourly.normal=120;
  const result=engine.evaluate(equivalent,parameters);
  assert.equal(result.opportunityCost,0);
  assert.equal(result.expectedRejectValue,result.expectedAcceptValue);
});

test('station deadline and shift end each independently override remaining time', () => {
  for(const target of ['station','shift']) {
    const input=scenario('A');
    if(target==='station') input.vehicle.requiredReturnAt='2026-09-07T10:30:00-06:00';
    else input.driver.shiftEnd='2026-09-07T10:30:00-06:00';
    assert.equal(engine.evaluate(input).recommendation,'NO RECOMENDADO',target);
    assert.ok(engine.evaluate(input).operationalBlocks.includes('No permite regresar a tiempo'));
  }
  const early=scenario('A'); early.driver.shiftStart='2026-09-07T11:00:00-06:00';
  assert.ok(engine.evaluate(early).operationalBlocks.includes('El turno aún no comienza'));
});

test('battery reserve is preserved even when nominal range covers the route', () => {
  const i=scenario('A'); i.vehicle.batteryPercent=12; i.vehicle.rangeKm=50;
  assert.ok(i.vehicle.rangeKm>i.trip.pickupKm+i.trip.tripKm+i.vehicle.destinationToStationKm+10);
  assert.equal(engine.evaluate(i).recommendation,'NO RECOMENDADO');
  assert.ok(engine.evaluate(i).operationalBlocks.includes('Falta autonomía para volver a estación'));
});

test('calendar dates, weekdays, fractional counts and non-JSON context are rejected', () => {
  for(const change of [i=>i.market.weekday=2,i=>i.market.hour=11,i=>i.market.now='2026-02-30T10:00:00Z',
    i=>i.market.now='2026-09-07T10:00:00',i=>i.driver.completedTrips=1.5,
    i=>i.market.traffic={speed:NaN},i=>i.trip.timestamp='2026-09-07T10:00:01-06:00']) {
    const input=scenario('A'); change(input); assert.throws(()=>engine.evaluate(input));
  }
});

const decisionMetadata={id:'10000000-0000-4000-8000-000000000001',createdAt:'2026-09-07T10:00:01-06:00'};
const outcomeMetadata={id:'10000000-0000-4000-8000-000000000002',createdAt:'2026-09-07T11:00:00-06:00'};
const observation=()=>({observedAt:'2026-09-07T10:55:00-06:00',driverAction:'accepted',actualFare:250,actualTripMinutes:25,actualTripKm:11,nextWaitMinutes:10,nextFare:125});

test('DecisionEvent survives JSON round trip and preserves complete immutable evidence', () => {
  const input=scenario('A'); input.market.weather={provider:'fixture',rainMm:4};
  const event=engine.createDecisionEvent(input,decisionMetadata);
  input.trip.fare=1; input.market.weather.rainMm=99;
  assert.equal(event.input.trip.fare,240); assert.equal(event.input.market.weather.rainMm,4);
  assert.equal(event.kind,'decision'); assert.equal(event.schemaVersion,'1.0.0');
  assert.ok(Object.isFrozen(event.input.trip)); assert.ok(Object.isFrozen(event.result.parameters.weights));
  const restored=clone(event);
  assert.deepEqual(engine.replayDecisionEvent(restored),event.result);
  restored.result.parameters.weights=Object.fromEntries(Object.entries(restored.result.parameters.weights).reverse());
  assert.deepEqual(engine.replayDecisionEvent(restored),event.result);
  restored.result.total=0; assert.throws(()=>engine.replayDecisionEvent(restored),/replay_mismatch/);
});

test('OutcomeEvent links driver, decision and provenance; errors are observed minus predicted', () => {
  const decision=engine.createDecisionEvent(scenario('A'),decisionMetadata), observed=observation();
  const outcome=engine.createOutcomeEvent(decision,observed,outcomeMetadata);
  assert.equal(outcome.decisionId,decision.id); assert.equal(outcome.driverId,decision.input.driver.driverId);
  assert.equal(outcome.source,'simulated');
  assert.deepEqual(outcome.predictionError,{fare:10,tripMinutes:3,tripKm:1,nextWaitMinutes:2});
  assert.deepEqual(clone(outcome),outcome); observed.actualFare=0;
  assert.equal(outcome.observation.actualFare,250); assert.ok(Object.isFrozen(outcome.observation));
});

test('rejection preserves unknown outcomes; no fabricated values or misleading wait error', () => {
  const decision=engine.createDecisionEvent(scenario('D'),decisionMetadata);
  const observed={...observation(),driverAction:'rejected',actualFare:null,actualTripMinutes:null,actualTripKm:null};
  const outcome=engine.createOutcomeEvent(decision,observed,outcomeMetadata);
  assert.deepEqual(outcome.predictionError,{fare:null,tripMinutes:null,tripKm:null,nextWaitMinutes:null});
  assert.equal(outcome.observation.nextFare,125);
  observed.actualFare=200;
  assert.throws(()=>engine.createOutcomeEvent(decision,observed,outcomeMetadata),/trip_not_accepted/);
});

test('invalid outcome, identifier, ordering and tampered evidence cannot be linked', () => {
  const decision=engine.createDecisionEvent(scenario('A'),decisionMetadata);
  assert.throws(()=>engine.createDecisionEvent(scenario('A'),{...decisionMetadata,id:'bad'}));
  assert.throws(()=>engine.createOutcomeEvent(decision,observation(),decisionMetadata),/duplicate/);
  assert.throws(()=>engine.createOutcomeEvent(decision,observation(),{...outcomeMetadata,createdAt:'2026-09-07T09:00:00-06:00'}));
  for(const change of [o=>o.actualFare=-1,o=>delete o.nextFare,o=>o.driverAction='maybe',o=>o.observedAt='2026-09-07T09:00:00-06:00']) {
    const observed=observation(); change(observed); assert.throws(()=>engine.createOutcomeEvent(decision,observed,outcomeMetadata));
  }
  const altered=clone(decision); altered.input.trip.fare+=500;
  assert.throws(()=>engine.createOutcomeEvent(altered,observation(),outcomeMetadata),/replay_mismatch/);
});

test('same offer across 05,07,10,14,18,22,01: fixed context is invariant; automatic priors explain changes', () => {
  const hours=[5,7,10,14,18,22,1];
  let prior;
  for (const hour of hours) {
    const i=scenario('C'); i.market.hour=hour;
    const now=new Date(Date.UTC(2026,8,7,hour));
    i.market.now=now.toISOString(); i.trip.timestamp=i.market.now;
    i.driver.shiftStart=new Date(now.getTime()-7200000).toISOString();
    i.driver.shiftEnd=new Date(now.getTime()+21600000).toISOString(); i.vehicle.requiredReturnAt=i.driver.shiftEnd;
    const r=engine.evaluate(i); if(prior) assert.deepEqual(r,prior); prior=r;
    i.market.demand='automatic';
    const auto=engine.evaluate(i); assert.equal(auto.demand,engine.defaultParameters().hourlyDemand[hour]);
  }
});
