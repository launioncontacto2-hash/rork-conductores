'use strict';

// Pure adapter around the canonical engine. This file owns the laboratory envelope;
// it deliberately does not copy or reimplement decision logic.
const engine = require('../supabase/functions/_shared/dori-copilot.js');

const clone = value => JSON.parse(JSON.stringify(value));
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?(?:Z|[+-]\d{2}:\d{2})$/;

function instant(value, name) {
  if (typeof value !== 'string' || !ISO.test(value) || !Number.isFinite(Date.parse(value))) {
    throw new Error(`invalid_${name}`);
  }
  return Date.parse(value);
}

function assertText(value, name) {
  if (typeof value !== 'string' || value.trim() === '') throw new Error(`invalid_${name}`);
}

function createSimulationCase({ testCaseId, createdAt, expiresAt, driverProfileId, stationId = null, input, expected }) {
  assertText(testCaseId, 'testCaseId');
  assertText(driverProfileId, 'driverProfileId');
  instant(createdAt, 'createdAt');
  instant(expiresAt, 'expiresAt');
  if (Date.parse(expiresAt) <= Date.parse(createdAt)) throw new Error('invalid_expiry');
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('invalid_input');
  if (input.source !== 'simulated') throw new Error('simulation_input_must_use_simulated_source');
  if (!['RECOMENDADO', 'NO RECOMENDADO'].includes(expected?.recommendation)) {
    throw new Error('invalid_expected_recommendation');
  }
  return Object.freeze({
    contractVersion: '1.0.0',
    testCaseId,
    createdAt,
    expiresAt,
    source: 'console_simulation',
    isSimulation: true,
    driverProfileId,
    stationId,
    input: clone(input),
    expected: Object.freeze({
      testCaseId,
      expectedRecommendation: expected.recommendation,
      expectedReasonCode: expected.reasonCode ?? null,
      actorProfileId: expected.actorProfileId ?? null,
      createdAt: expected.createdAt ?? createdAt,
      criterionVersion: expected.criterionVersion ?? 'lab-1.0.0',
    }),
  });
}

function toEngineInput(simulationCase) {
  if (!simulationCase?.isSimulation || simulationCase.source !== 'console_simulation') {
    throw new Error('simulation_marker_required');
  }
  // Expected is intentionally never copied into the engine input.
  return clone(simulationCase.input);
}

function evaluateSimulation(simulationCase, evaluationAt) {
  const evaluatedAt = evaluationAt ?? simulationCase.createdAt;
  const evaluatedMs = instant(evaluatedAt, 'evaluationAt');
  if (evaluatedMs > instant(simulationCase.expiresAt, 'expiresAt')) throw new Error('simulation_expired');
  const actual = engine.evaluate(toEngineInput(simulationCase));
  const expected = simulationCase.expected.expectedRecommendation;
  const match = expected === actual.recommendation;
  const classification = match
    ? expected === 'RECOMENDADO' ? 'correct_recommend' : 'correct_reject'
    : expected === 'RECOMENDADO' ? 'false_negative' : 'false_positive';
  return Object.freeze({
    contractVersion: simulationCase.contractVersion,
    testCaseId: simulationCase.testCaseId,
    expected,
    actual,
    match,
    classification,
    hasOperationalBlock: actual.operationalBlocks.length > 0,
    versions: Object.freeze({ modelVersion: actual.modelVersion, rulesVersion: actual.rulesVersion, parameterVersion: actual.parameterVersion }),
    evaluatedAt,
    isSimulation: true,
    source: 'console_simulation',
  });
}

module.exports = { createSimulationCase, toEngineInput, evaluateSimulation };
