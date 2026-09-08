/* Single source of decision logic, prepared for JavaScriptCore on iOS; tested in Node.
 * Pure, offline, no clock/network/randomness. Monetary values are MXN, distance km,
 * duration minutes. Provisional priors are assumptions, never learned predictions. */
(function (root) {
  'use strict';
  const defaults = {
    modelVersion: 'deterministic-0.1', rulesVersion: '0.1.0', parameterVersion: 'mxn-lab-0.1.0',
    weights: { time: 0.35, distance: 0.20, pickup: 0.15, destination: 0.20, operational: 0.10 },
    thresholds: { low: 58, normal: 65, high: 70 },
    referenceNetHourly: 180, referenceNetPerKm: 12, wearCostPerKm: 1.2,
    pickupLimitMinutes: 30, batteryReservePercent: 10, rangeReserveKm: 10,
    stationSpeedKmh: 25, returnBufferMinutes: 10, boundaryBand: 3, economicBoundaryBand: 3,
    maxOfferAgeSeconds: 60,
    // Net connected-hour alternatives, including idle time. Calibrate with outcomes.
    alternativeNetHourly: { low: 65, normal: 120, high: 190 },
    destinationWaitMinutes: { low: 25, normal: 12, high: 5 },
    hourlyDemand: ['low','low','low','low','low','low','normal','high','high','normal','normal','normal','normal','normal','normal','normal','normal','high','high','normal','normal','normal','low','low']
  };
  const clone = x => JSON.parse(JSON.stringify(x));
  function freeze(x) {
    if (x && typeof x === 'object') { Object.values(x).forEach(freeze); Object.freeze(x); }
    return x;
  }
  function record(x, name) {
    if (!x || typeof x !== 'object' || Array.isArray(x)) throw new Error('invalid_' + name);
  }
  function jsonValue(x, name) {
    if (x === null || typeof x === 'string' || typeof x === 'boolean') return;
    if (typeof x === 'number' && Number.isFinite(x)) return;
    if (Array.isArray(x)) { for (const value of x) jsonValue(value, name); return; }
    if (x && Object.getPrototypeOf(x) === Object.prototype) { Object.values(x).forEach(v => jsonValue(v, name)); return; }
    throw new Error('invalid_' + name);
  }
  const clamp = x => Math.max(0, Math.min(100, x));
  function numeric(x, name, min, max) {
    if (typeof x !== 'number' || !Number.isFinite(x) || x < min || x > max) throw new Error('invalid_' + name);
  }
  function label(x, name) { if (typeof x !== 'string' || !x.trim() || x.length > 200) throw new Error('invalid_' + name); }
  function timestamp(x, name) {
    label(x, name);
    // Require an explicit offset for reproducible parsing on every device.
    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?(Z|[+-]\d{2}:\d{2})$/.test(x)
      || !Number.isFinite(Date.parse(x))) throw new Error('invalid_' + name);
    const local = new Date(x.slice(0,19) + 'Z');
    if (local.toISOString().slice(0,19) !== x.slice(0,19)) throw new Error('invalid_' + name);
  }
  function oneOf(x, values, name) { if (!values.includes(x)) throw new Error('invalid_' + name); }
  function uuid(x, name) {
    if (typeof x !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(x)) throw new Error('invalid_' + name);
  }
  function configCheck(p) {
    record(p, 'parameters');
    if (p.modelVersion !== defaults.modelVersion || p.rulesVersion !== defaults.rulesVersion) throw new Error('unsupported_engine_version');
    for (const key of ['modelVersion','rulesVersion','parameterVersion']) label(p[key], key);
    for (const key of ['weights','thresholds','alternativeNetHourly','destinationWaitMinutes']) record(p[key], key);
    if (Object.keys(p.weights).sort().join() !== Object.keys(defaults.weights).sort().join()) throw new Error('invalid_weights');
    for (const key of Object.keys(defaults.weights)) numeric(p.weights[key], key, 0, 1);
    if (Math.abs(Object.values(p.weights).reduce((a,b) => a+b, 0) - 1) > 1e-9) throw new Error('invalid_weights');
    for (const key of ['referenceNetHourly','referenceNetPerKm','pickupLimitMinutes','stationSpeedKmh']) numeric(p[key], key, 0.01, 10000);
    for (const key of ['wearCostPerKm','rangeReserveKm','returnBufferMinutes','boundaryBand','economicBoundaryBand','maxOfferAgeSeconds']) numeric(p[key], key, 0, 1000);
    numeric(p.batteryReservePercent, 'batteryReservePercent', 0, 100);
    for (const d of ['low','normal','high']) {
      numeric(p.thresholds[d], 'threshold', 0, 100);
      numeric(p.alternativeNetHourly[d], 'alternativeNetHourly', 0, 10000);
      numeric(p.destinationWaitMinutes[d], 'wait', 0, 1440);
    }
    if (!Array.isArray(p.hourlyDemand) || p.hourlyDemand.length !== 24 || p.hourlyDemand.some(d => !['low','normal','high'].includes(d))) throw new Error('invalid_hourlyDemand');
    if (!(p.thresholds.low <= p.thresholds.normal && p.thresholds.normal <= p.thresholds.high)) throw new Error('invalid_threshold_order');
    if (p.parameterVersion === defaults.parameterVersion && canonical(p) !== canonical(defaults)) throw new Error('changed_parameters_require_new_version');
  }
  /** @param {import('./dori-copilot').TripCandidate} t */
  function validateTripCandidate(t) {
    record(t, 'TripCandidate');
    for (const key of ['fare','pickupMinutes','pickupKm','tripMinutes','tripKm']) numeric(t[key], key, key === 'tripMinutes' ? 0.1 : 0, 100000);
    for (const key of ['origin','destination']) label(t[key], key);
    timestamp(t.timestamp, 'trip_timestamp');
  }
  /** @param {import('./dori-copilot').MarketContext} m */
  function validateMarketContext(m) {
    record(m, 'MarketContext'); timestamp(m.now, 'market_now');
    numeric(m.hour, 'hour', 0, 23); numeric(m.weekday, 'weekday', 1, 7);
    if (!Number.isInteger(m.hour) || !Number.isInteger(m.weekday)) throw new Error('invalid_calendar');
    // weekday uses ISO Monday=1 ... Sunday=7, in the timestamp's explicit local offset.
    const local = new Date(m.now.slice(0,19) + 'Z');
    if (m.hour !== local.getUTCHours() || m.weekday !== (local.getUTCDay() || 7)) throw new Error('inconsistent_calendar');
    if (!['low','normal','high','automatic'].includes(m.demand)) throw new Error('invalid_demand');
    for (const key of ['originZone','destinationZone']) label(m[key], key);
    numeric(m.destinationValue, 'destinationValue', 0, 100);
    numeric(m.nextWaitMinutes, 'nextWaitMinutes', 0, 1440);
    numeric(m.repositionKm, 'repositionKm', 0, 1000); numeric(m.repositionMinutes, 'repositionMinutes', 0, 1440);
    for (const key of ['historicalDemand','forecastDemand']) {
      if (m[key] !== null) oneOf(m[key], ['low','normal','high'], key);
    }
    for (const key of ['traffic','events','weather']) jsonValue(m[key], key);
  }
  /** @param {import('./dori-copilot').VehicleContext} v */
  function validateVehicleContext(v) {
    record(v, 'VehicleContext');
    label(v.vehicleId, 'vehicleId'); numeric(v.batteryPercent, 'battery', 0, 100);
    for (const key of ['rangeKm','consumptionKwhPerKm','energyCostPerKm','odometerKm','distanceToStationKm','destinationToStationKm']) numeric(v[key], key, 0, 1000000);
    timestamp(v.requiredReturnAt, 'requiredReturnAt');
  }
  /** @param {import('./dori-copilot').DriverContext} d */
  function validateDriverContext(d) {
    record(d, 'DriverContext'); timestamp(d.shiftStart, 'shiftStart'); timestamp(d.shiftEnd, 'shiftEnd');
    label(d.driverId, 'driverId');
    for (const key of ['remainingMinutes','connectedMinutes','accumulatedIncome','completedTrips']) numeric(d[key], key, 0, 1000000);
    if (Date.parse(d.shiftEnd) <= Date.parse(d.shiftStart)) throw new Error('invalid_shift');
    if (!Number.isInteger(d.completedTrips)) throw new Error('invalid_completedTrips');
  }
  function validate(input, parameters) {
    record(input, 'DecisionInput');
    validateTripCandidate(input.trip); validateMarketContext(input.market);
    validateVehicleContext(input.vehicle); validateDriverContext(input.driver);
    oneOf(input.source, ['simulated','historical','manual'], 'source');
    const ageSeconds = (Date.parse(input.market.now) - Date.parse(input.trip.timestamp)) / 1000;
    if (ageSeconds < 0 || ageSeconds > parameters.maxOfferAgeSeconds) throw new Error('stale_offer');
    jsonValue(input, 'DecisionInput');
  }
  /** @param {import('./dori-copilot').DecisionInput} input
   * @param {import('./dori-copilot').DecisionParameters=} supplied
   * @returns {import('./dori-copilot').DecisionResult} */
  function evaluate(input, supplied) {
    const sourceParameters = supplied === undefined ? defaults : supplied;
    configCheck(sourceParameters); jsonValue(sourceParameters, 'parameters');
    const p = clone(sourceParameters); validate(input, p);
    const { trip: t, market: m, vehicle: v, driver: d } = input;
    const demand = m.demand === 'automatic' ? p.hourlyDemand[m.hour] : m.demand;
    const wait = m.demand === 'automatic' ? p.destinationWaitMinutes[demand] : m.nextWaitMinutes;
    const km = t.pickupKm + t.tripKm + m.repositionKm;
    const activeMinutes = t.pickupMinutes + t.tripMinutes;
    const connectedMinutes = activeMinutes + m.repositionMinutes + wait;
    const net = t.fare - km * (v.energyCostPerKm + p.wearCostPerKm);
    const netHourly = net * 60 / connectedMinutes;
    const netPerKm = net / Math.max(km, 0.1);
    const returnMinutes = v.destinationToStationKm / p.stationSpeedKmh * 60 + p.returnBufferMinutes;
    const deadlineMinutes = Math.min(d.remainingMinutes, (Date.parse(d.shiftEnd) - Date.parse(m.now)) / 60000,
      (Date.parse(v.requiredReturnAt) - Date.parse(m.now)) / 60000);
    // rangeKm is the remaining range at the CURRENT charge, not the full-charge range.
    const batteryReserveKm = v.batteryPercent > 0 ? v.rangeKm * p.batteryReservePercent / v.batteryPercent : 0;
    const requiredKm = t.pickupKm + t.tripKm + v.destinationToStationKm + Math.max(p.rangeReserveKm, batteryReserveKm);
    const blocks = [];
    if (v.batteryPercent <= p.batteryReservePercent) blocks.push('Batería insuficiente');
    if (v.rangeKm < requiredKm) blocks.push('Falta autonomía para volver a estación');
    if (activeMinutes + returnMinutes > deadlineMinutes) blocks.push('No permite regresar a tiempo');
    if (Date.parse(m.now) < Date.parse(d.shiftStart)) blocks.push('El turno aún no comienza');
    const scores = {
      time: clamp(netHourly / p.referenceNetHourly * 100),
      distance: clamp(netPerKm / p.referenceNetPerKm * 100),
      pickup: clamp(100 * (1 - t.pickupMinutes / p.pickupLimitMinutes)),
      destination: m.destinationValue,
      operational: Math.min(clamp((v.rangeKm - requiredKm) / Math.max(requiredKm, 1) * 100),
        clamp((deadlineMinutes - activeMinutes - returnMinutes) / Math.max(activeMinutes + returnMinutes, 1) * 100))
    };
    const total = Object.keys(scores).reduce((sum,k) => sum + scores[k] * p.weights[k], 0);
    // Compare net values over the SAME connected-time horizon. Reject prior includes waiting.
    const expectedAcceptValue = net;
    const expectedRejectValue = p.alternativeNetHourly[demand] * connectedMinutes / 60;
    const opportunityCost = expectedRejectValue - expectedAcceptValue;
    const threshold = p.thresholds[demand];
    const recommended = blocks.length === 0 && total >= threshold && expectedAcceptValue >= expectedRejectValue;
    const reasons = blocks.slice();
    const descriptions = {
      time: ['Buen pago para el tiempo','Pago bajo para el tiempo'],
      distance: ['Buen pago para la distancia','Pago bajo para la distancia'],
      pickup: ['Recogida cercana','Mucho tiempo para recoger'],
      destination: ['Destino conveniente','Destino poco conveniente'],
      operational: ['Permite volver con margen','Poco margen para volver']
    };
    if (!recommended && expectedAcceptValue < expectedRejectValue) reasons.push('Conviene esperar otra oportunidad');
    Object.keys(scores).sort((a,b) => recommended ? scores[b]-scores[a] : scores[a]-scores[b]).forEach(k => {
      if (recommended ? scores[k] >= threshold : scores[k] < threshold) reasons.push(descriptions[k][recommended ? 0 : 1]);
    });
    if (!reasons.length) reasons.push(recommended ? 'Viaje conveniente en este momento' : 'El viaje deja poco margen');
    return freeze({
      recommendation: recommended ? 'RECOMENDADO' : 'NO RECOMENDADO', reasons: reasons.slice(0,3),
      scores, total, threshold, expectedAcceptValue, expectedRejectValue, opportunityCost,
      netConnectedHourly: netHourly, connectedMinutes, nextWaitMinutes: wait, demand, operationalBlocks: blocks,
      requiredRangeKm: requiredKm, requiredReturnMinutes: activeMinutes + returnMinutes, availableMinutes: deadlineMinutes,
      nearBoundary: Math.abs(total - threshold) <= p.boundaryBand || Math.abs(netHourly - p.alternativeNetHourly[demand]) <= p.economicBoundaryBand,
      modelVersion: p.modelVersion, rulesVersion: p.rulesVersion, parameterVersion: p.parameterVersion,
      parameters: p, assumptions: ['Valores provisionales de laboratorio', 'Demanda y espera simuladas; sin datos de Uber']
    });
  }
  /** @returns {import('./dori-copilot').DecisionEvent} */
  function createDecisionEvent(input, metadata, parameters) {
    record(metadata, 'metadata'); uuid(metadata.id, 'id'); timestamp(metadata.createdAt, 'createdAt');
    // Never accept a caller-provided recommendation. Snapshot exactly what was evaluated.
    const result = evaluate(input, parameters);
    return freeze({ schemaVersion: '1.0.0', kind: 'decision', id: metadata.id,
      createdAt: metadata.createdAt, input: clone(input), result });
  }
  function canonical(value) {
    if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
    if (value && typeof value === 'object') return '{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
    return JSON.stringify(value);
  }
  function replayDecisionEvent(event) {
    record(event, 'DecisionEvent'); uuid(event.id, 'id'); timestamp(event.createdAt, 'createdAt');
    if (event.schemaVersion !== '1.0.0' || event.kind !== 'decision') throw new Error('unsupported_event_schema');
    record(event.result, 'result');
    const actual = evaluate(event.input, event.result.parameters);
    if (canonical(actual) !== canonical(event.result)) throw new Error('decision_replay_mismatch');
    return actual;
  }
  /** @returns {import('./dori-copilot').OutcomeEvent} */
  function createOutcomeEvent(decision, observation, metadata) {
    const result = replayDecisionEvent(decision);
    record(metadata, 'metadata'); uuid(metadata.id, 'id'); timestamp(metadata.createdAt, 'createdAt');
    if (metadata.id === decision.id) throw new Error('duplicate_event_id');
    if (Date.parse(metadata.createdAt) < Date.parse(decision.createdAt)) throw new Error('outcome_before_decision');
    record(observation, 'OutcomeObservation'); timestamp(observation.observedAt, 'observedAt');
    if (Date.parse(observation.observedAt) < Date.parse(decision.input.market.now)) throw new Error('observation_before_offer');
    oneOf(observation.driverAction, ['accepted','rejected','unknown'], 'driverAction');
    for (const key of ['actualFare','actualTripMinutes','actualTripKm','nextWaitMinutes','nextFare']) {
      if (observation[key] !== null) numeric(observation[key], key, 0, 1000000);
    }
    if (observation.driverAction !== 'accepted' && ['actualFare','actualTripMinutes','actualTripKm'].some(k => observation[k] !== null)) throw new Error('trip_not_accepted');
    jsonValue(observation, 'OutcomeObservation');
    const error = (observed, predicted) => observed === null ? null : observed - predicted;
    return freeze({ schemaVersion: '1.0.0', kind: 'outcome', id: metadata.id, createdAt: metadata.createdAt,
      decisionId: decision.id, driverId: decision.input.driver.driverId, source: decision.input.source,
      observation: clone(observation), predictionError: {
        fare: error(observation.actualFare, decision.input.trip.fare),
        tripMinutes: error(observation.actualTripMinutes, decision.input.trip.tripMinutes),
        tripKm: error(observation.actualTripKm, decision.input.trip.tripKm),
        // Rejecting reveals a different path: do not compare it to the destination wait.
        nextWaitMinutes: observation.driverAction === 'accepted' ? error(observation.nextWaitMinutes, result.nextWaitMinutes) : null
      } });
  }
  const api = { evaluate, createDecisionEvent, replayDecisionEvent, createOutcomeEvent,
    validateTripCandidate, validateMarketContext, validateVehicleContext, validateDriverContext,
    defaultParameters: () => clone(defaults), evaluateJSON: text => JSON.stringify(evaluate(JSON.parse(text))) };
  root.DoriCopilot = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(globalThis);
