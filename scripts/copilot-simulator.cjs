'use strict';

// The simulator imports the production V0.1 engine. Decision logic must never live here.
const engine = require('../ios-turno-ev/TurnoEV/Resources/dori-copilot.js');
const { scenario } = require('./copilot-fixtures.cjs');

const HOURS = Object.freeze([5, 7, 10, 14, 18, 22, 1]);
const DEFAULT_GRID = Object.freeze({
  hours: HOURS,
  demands: Object.freeze(['low', 'normal', 'high']),
  batteries: Object.freeze([5, 30, 80]),
  remainingMinutes: Object.freeze([20, 120, 360]),
  pickupMinutes: Object.freeze([2, 35]),
  fares: Object.freeze([60, 115, 240, 450]),
  tripKm: Object.freeze([3, 12, 40]),
  destinationValues: Object.freeze([20, 65, 95])
});

const clone = value => JSON.parse(JSON.stringify(value));
const close = (left, right, tolerance = 1e-9) =>
  Math.abs(left - right) <= tolerance * Math.max(1, Math.abs(left), Math.abs(right));

function localTimestamp(hour) {
  if (!Number.isInteger(hour) || hour < 0 || hour > 23) throw new Error('invalid_simulation_hour');
  return `2026-09-07T${String(hour).padStart(2, '0')}:00:00-06:00`;
}

function applyHour(input, hour) {
  const value = clone(input);
  const now = localTimestamp(hour);
  value.trip.timestamp = now;
  value.market.now = now;
  value.market.hour = hour;
  value.market.weekday = 1;
  value.driver.shiftStart = '2026-09-07T00:00:00-06:00';
  value.driver.shiftEnd = '2026-09-08T08:00:00-06:00';
  value.vehicle.requiredReturnAt = value.driver.shiftEnd;
  return value;
}

function applyVariables(input, variables = {}) {
  const value = applyHour(input, variables.hour ?? input.market.hour);
  if (variables.demand !== undefined) value.market.demand = variables.demand;
  if (variables.battery !== undefined) value.vehicle.batteryPercent = variables.battery;
  if (variables.remaining !== undefined) value.driver.remainingMinutes = variables.remaining;
  if (variables.pickup !== undefined) {
    value.trip.pickupMinutes = variables.pickup;
    value.trip.pickupKm = variables.pickup / 3;
  }
  if (variables.fare !== undefined) value.trip.fare = variables.fare;
  if (variables.distance !== undefined) value.trip.tripKm = variables.distance;
  if (variables.destinationValue !== undefined) value.market.destinationValue = variables.destinationValue;
  return value;
}

function baselineDecisions(result, minimumNetHourly) {
  return {
    acceptAll: true,
    minimumNetConnectedHourly: result.netConnectedHourly >= minimumNetHourly
  };
}

function evaluateInput(input, { minimumNetHourly = 120 } = {}) {
  if (typeof minimumNetHourly !== 'number' || !Number.isFinite(minimumNetHourly)) {
    throw new Error('invalid_minimum_net_hourly');
  }
  const result = engine.evaluate(input);
  return {
    input: clone(input),
    result,
    baselines: baselineDecisions(result, minimumNetHourly)
  };
}

function runIndividual({ fixture = 'A', variables = {}, minimumNetHourly = 120 } = {}) {
  if (!['A', 'B', 'C', 'D', 'E'].includes(fixture)) throw new Error('invalid_fixture');
  return evaluateInput(applyVariables(scenario(fixture), variables), { minimumNetHourly });
}

function runHourlySweep(input = scenario('C'), {
  hours = HOURS,
  demand = 'automatic',
  minimumNetHourly = 120
} = {}) {
  return hours.map(hour => {
    const value = applyVariables(input, { hour, demand });
    return evaluateInput(value, { minimumNetHourly });
  });
}

function anomaly(type, message, input, result, related = undefined) {
  const report = {
    type,
    message,
    input: clone(input),
    recommendation: result.recommendation,
    score: result.total,
    threshold: result.threshold,
    expectedAcceptValue: result.expectedAcceptValue,
    expectedRejectValue: result.expectedRejectValue,
    opportunityCost: result.opportunityCost,
    operationalBlocks: clone(result.operationalBlocks),
    reasons: clone(result.reasons)
  };
  if (related !== undefined) report.related = clone(related);
  return report;
}

function inspectResult(input, result) {
  const anomalies = [];
  const finite = ['total', 'threshold', 'expectedAcceptValue', 'expectedRejectValue', 'opportunityCost'];
  if (finite.some(key => !Number.isFinite(result[key]))) {
    anomalies.push(anomaly('non_finite_result', 'El motor produjo un valor no finito.', input, result));
    return anomalies;
  }
  if (result.total < 0 || result.total > 100) {
    anomalies.push(anomaly('score_out_of_range', 'La puntuación salió del intervalo 0–100.', input, result));
  }
  const weighted = Object.keys(result.scores).reduce(
    (sum, key) => sum + result.scores[key] * result.parameters.weights[key], 0
  );
  if (!close(weighted, result.total)) {
    anomalies.push(anomaly('weighted_score_mismatch', 'La puntuación no coincide con sus componentes ponderados.', input, result));
  }
  if (!close(result.opportunityCost, result.expectedRejectValue - result.expectedAcceptValue)) {
    anomalies.push(anomaly('opportunity_cost_mismatch', 'El costo de oportunidad no es rechazar menos aceptar.', input, result));
  }
  if (result.threshold !== result.parameters.thresholds[result.demand]) {
    anomalies.push(anomaly('threshold_mismatch', 'El umbral no corresponde a la demanda resuelta.', input, result));
  }
  const shouldRecommend = result.operationalBlocks.length === 0
    && result.total >= result.threshold
    && result.expectedAcceptValue >= result.expectedRejectValue;
  if ((result.recommendation === 'RECOMENDADO') !== shouldRecommend) {
    anomalies.push(anomaly('decision_rule_mismatch', 'La recomendación contradice las reglas declaradas.', input, result));
  }
  if (result.recommendation === 'RECOMENDADO' && result.operationalBlocks.length > 0) {
    anomalies.push(anomaly('operational_veto_ignored', 'Se recomendó un viaje con bloqueo operativo.', input, result));
  }
  if (!Array.isArray(result.reasons) || result.reasons.length < 1 || result.reasons.length > 3) {
    anomalies.push(anomaly('invalid_reason_count', 'La salida no contiene entre una y tres razones.', input, result));
  }
  return anomalies;
}

function compareImprovement(name, input, result, mutate) {
  const improvedInput = clone(input);
  mutate(improvedInput);
  const improved = engine.evaluate(improvedInput);
  const anomalies = [];
  if (improved.total + 1e-9 < result.total) {
    anomalies.push(anomaly(
      `${name}_lowered_score`,
      `Mejorar ${name} redujo la puntuación.`,
      improvedInput,
      improved,
      { originalInput: input, originalRecommendation: result.recommendation, originalScore: result.total }
    ));
  }
  if (result.recommendation === 'RECOMENDADO' && improved.recommendation !== 'RECOMENDADO') {
    anomalies.push(anomaly(
      `${name}_reversed_recommendation`,
      `Mejorar ${name} cambió RECOMENDADO a NO RECOMENDADO.`,
      improvedInput,
      improved,
      { originalInput: input, originalRecommendation: result.recommendation, originalScore: result.total }
    ));
  }
  return anomalies;
}

function inspectMetamorphic(input, result) {
  return [
    ...compareImprovement('fare', input, result, value => { value.trip.fare += 1; }),
    ...compareImprovement('battery', input, result, value => {
      value.vehicle.batteryPercent = Math.min(100, value.vehicle.batteryPercent + 1);
    }),
    ...compareImprovement('remaining_time', input, result, value => { value.driver.remainingMinutes += 1; }),
    ...compareImprovement('pickup_time', input, result, value => {
      value.trip.pickupMinutes = Math.max(0, value.trip.pickupMinutes - 1);
    })
  ];
}

function blankStrategy() {
  return { accepted: 0, rejected: 0, expectedValue: 0, operationallyBlockedAcceptances: 0 };
}

function recordStrategy(strategy, accepts, result) {
  strategy[accepts ? 'accepted' : 'rejected'] += 1;
  strategy.expectedValue += accepts ? result.expectedAcceptValue : result.expectedRejectValue;
  if (accepts && result.operationalBlocks.length > 0) strategy.operationallyBlockedAcceptances += 1;
}

function validateGrid(grid) {
  const keys = Object.keys(DEFAULT_GRID);
  for (const key of keys) {
    if (!Array.isArray(grid[key]) || grid[key].length === 0) throw new Error(`invalid_grid_${key}`);
  }
}

function *gridGroups(grid = DEFAULT_GRID) {
  validateGrid(grid);
  for (const hour of grid.hours)
  for (const battery of grid.batteries)
  for (const remaining of grid.remainingMinutes)
  for (const pickup of grid.pickupMinutes)
  for (const fare of grid.fares)
  for (const distance of grid.tripKm)
  for (const destinationValue of grid.destinationValues) {
    const values = { hour, battery, remaining, pickup, fare, distance, destinationValue };
    yield grid.demands.map(demand => applyVariables(scenario('A'), { ...values, demand }));
  }
}

function runMassSimulation({ grid = DEFAULT_GRID, minimumNetHourly = 120 } = {}) {
  if (typeof minimumNetHourly !== 'number' || !Number.isFinite(minimumNetHourly)) {
    throw new Error('invalid_minimum_net_hourly');
  }
  const strategies = {
    dori: blankStrategy(),
    acceptAll: blankStrategy(),
    minimumNetConnectedHourly: blankStrategy()
  };
  const anomalies = [];
  const boundarySamples = [];
  let nearBoundaryCount = 0;
  let scenarioCount = 0;
  let metamorphicChecks = 0;
  for (const group of gridGroups(grid)) {
    const demandResults = [];
    for (const input of group) {
      const evaluated = evaluateInput(input, { minimumNetHourly });
      const result = evaluated.result;
      scenarioCount += 1;
      anomalies.push(...inspectResult(input, result));
      const metamorphic = inspectMetamorphic(input, result);
      metamorphicChecks += 4;
      anomalies.push(...metamorphic);
      if (result.nearBoundary) {
        nearBoundaryCount += 1;
        if (boundarySamples.length < 20) {
          boundarySamples.push(anomaly('near_boundary', 'Decisión cercana al límite; requiere seguimiento.', input, result));
        }
      }
      const doriAccepts = result.recommendation === 'RECOMENDADO';
      recordStrategy(strategies.dori, doriAccepts, result);
      recordStrategy(strategies.acceptAll, true, result);
      recordStrategy(strategies.minimumNetConnectedHourly, evaluated.baselines.minimumNetConnectedHourly, result);
      demandResults.push({ input, result });
    }
    const byDemand = Object.fromEntries(demandResults.map(item => [item.result.demand, item]));
    for (const [harder, easier] of [['high', 'normal'], ['normal', 'low']]) {
      if (byDemand[harder] && byDemand[easier]
          && byDemand[harder].result.recommendation === 'RECOMENDADO'
          && byDemand[easier].result.recommendation !== 'RECOMENDADO') {
        anomalies.push(anomaly(
          'demand_order_reversal',
          `${harder} fue RECOMENDADO, pero el mismo viaje en ${easier} no.`,
          byDemand[easier].input,
          byDemand[easier].result,
          {
            harderDemand: harder,
            recommendation: byDemand[harder].result.recommendation,
            score: byDemand[harder].result.total,
            threshold: byDemand[harder].result.threshold,
            opportunityCost: byDemand[harder].result.opportunityCost
          }
        ));
      }
    }
  }
  for (const strategy of Object.values(strategies)) {
    strategy.expectedValue = Number(strategy.expectedValue.toFixed(6));
    strategy.averageExpectedValue = scenarioCount === 0 ? 0 : Number((strategy.expectedValue / scenarioCount).toFixed(6));
  }
  return {
    simulatorVersion: '1.0.0',
    engineVersion: engine.defaultParameters().modelVersion,
    parameterVersion: engine.defaultParameters().parameterVersion,
    grid: clone(grid),
    minimumNetHourly,
    scenarioCount,
    metamorphicChecks,
    anomalyCount: anomalies.length,
    anomalies,
    nearBoundaryCount,
    boundarySamples,
    strategies
  };
}

module.exports = {
  HOURS,
  DEFAULT_GRID,
  applyHour,
  applyVariables,
  evaluateInput,
  runIndividual,
  runHourlySweep,
  inspectResult,
  inspectMetamorphic,
  runMassSimulation
};
