/** Block 1 wire contracts. Money: MXN net of platform commission; distances: km;
 * durations: minutes. Times: ISO 8601 with seconds and explicit UTC offset.
 * Nullable observations mean unknown, never zero. No provider-specific payloads. */
export type DemandLevel = 'low' | 'normal' | 'high';
export type DataSource = 'simulated' | 'historical' | 'manual';
export type JSONValue = null | string | number | boolean | JSONValue[] | { [key: string]: JSONValue };

export interface TripCandidate {
  /** Expected amount paid to the driver after platform commission, before vehicle costs. */
  fare: number;
  pickupMinutes: number;
  pickupKm: number;
  tripMinutes: number;
  tripKm: number;
  origin: string;
  destination: string;
  timestamp: string;
}
export interface MarketContext {
  now: string;
  /** Local hour in now's explicit offset; integer 0...23. */
  hour: number;
  /** ISO weekday in now's explicit offset; Monday=1 ... Sunday=7. */
  weekday: number;
  originZone: string;
  destinationZone: string;
  /** automatic uses the versioned illustrative hourly prior, never a live forecast. */
  demand: DemandLevel | 'automatic';
  historicalDemand: DemandLevel | null;
  forecastDemand: DemandLevel | null;
  /** Expected wait at destination after repositioning. Automatic uses the prior instead. */
  nextWaitMinutes: number;
  /** Explicit provisional destination rating, 0...100; not a trained prediction. */
  destinationValue: number;
  repositionKm: number;
  repositionMinutes: number;
  /** Reserved inputs preserved in events, not used in V0.1 decisions. */
  traffic: JSONValue;
  events: JSONValue;
  weather: JSONValue;
}
export interface VehicleContext {
  vehicleId: string;
  batteryPercent: number;
  /** Estimated REMAINING range at current charge, including reserve still in the pack. */
  rangeKm: number;
  consumptionKwhPerKm: number;
  energyCostPerKm: number;
  odometerKm: number;
  distanceToStationKm: number;
  /** Required additional input: safe return distance FROM THE OFFER'S DESTINATION. */
  destinationToStationKm: number;
  requiredReturnAt: string;
}
export interface DriverContext {
  driverId: string;
  shiftStart: string;
  shiftEnd: string;
  /** Conservative remaining time; absolute shift/return deadlines can shorten it. */
  remainingMinutes: number;
  connectedMinutes: number;
  accumulatedIncome: number;
  completedTrips: number;
}
export interface DecisionInput {
  trip: TripCandidate;
  market: MarketContext;
  vehicle: VehicleContext;
  driver: DriverContext;
  source: DataSource;
}
export interface BlockValues {
  time: number;
  distance: number;
  pickup: number;
  destination: number;
  operational: number;
}
export interface DecisionParameters {
  modelVersion: 'deterministic-0.1';
  rulesVersion: '0.1.0';
  parameterVersion: string;
  weights: BlockValues;
  thresholds: Record<DemandLevel, number>;
  referenceNetHourly: number;
  referenceNetPerKm: number;
  wearCostPerKm: number;
  pickupLimitMinutes: number;
  batteryReservePercent: number;
  rangeReserveKm: number;
  stationSpeedKmh: number;
  returnBufferMinutes: number;
  /** Score points. */
  boundaryBand: number;
  /** MXN per connected hour. */
  economicBoundaryBand: number;
  maxOfferAgeSeconds: number;
  alternativeNetHourly: Record<DemandLevel, number>;
  destinationWaitMinutes: Record<DemandLevel, number>;
  hourlyDemand: DemandLevel[];
}
export interface DecisionResult {
  recommendation: 'RECOMENDADO' | 'NO RECOMENDADO';
  /** One to three Spanish reasons; the rest of this object is internal-only. */
  reasons: string[];
  scores: BlockValues;
  total: number;
  threshold: number;
  /** Net MXN for accept/reject, over the SAME connectedMinutes horizon. */
  expectedAcceptValue: number;
  expectedRejectValue: number;
  /** Reject minus accept: positive favors rejecting, zero is equivalent, negative favors accepting. */
  opportunityCost: number;
  netConnectedHourly: number;
  connectedMinutes: number;
  nextWaitMinutes: number;
  demand: DemandLevel;
  operationalBlocks: string[];
  requiredRangeKm: number;
  requiredReturnMinutes: number;
  availableMinutes: number;
  nearBoundary: boolean;
  modelVersion: string;
  rulesVersion: string;
  parameterVersion: string;
  parameters: DecisionParameters;
  assumptions: string[];
}
export interface EventMetadata { id: string; createdAt: string }
export interface DecisionEvent extends EventMetadata {
  schemaVersion: '1.0.0';
  kind: 'decision';
  input: DecisionInput;
  result: DecisionResult;
}
export interface OutcomeObservation {
  observedAt: string;
  driverAction: 'accepted' | 'rejected' | 'unknown';
  actualFare: number | null;
  /** Ride only, excluding pickup and waiting, like TripCandidate.tripMinutes/tripKm. */
  actualTripMinutes: number | null;
  actualTripKm: number | null;
  nextWaitMinutes: number | null;
  nextFare: number | null;
}
export interface OutcomeEvent extends EventMetadata {
  schemaVersion: '1.0.0';
  kind: 'outcome';
  decisionId: string;
  driverId: string;
  source: DataSource;
  observation: OutcomeObservation;
  /** Observed minus predicted; unavailable or inapplicable comparisons remain null. */
  predictionError: { fare: number | null; tripMinutes: number | null; tripKm: number | null; nextWaitMinutes: number | null };
}
export function defaultParameters(): DecisionParameters;
export function validateTripCandidate(value: TripCandidate): void;
export function validateMarketContext(value: MarketContext): void;
export function validateVehicleContext(value: VehicleContext): void;
export function validateDriverContext(value: DriverContext): void;
export function evaluate(input: DecisionInput, parameters?: DecisionParameters): DecisionResult;
export function evaluateJSON(input: string): string;
export function createDecisionEvent(input: DecisionInput, metadata: EventMetadata, parameters?: DecisionParameters): DecisionEvent;
export function replayDecisionEvent(event: DecisionEvent): DecisionResult;
export function createOutcomeEvent(decision: DecisionEvent, observation: OutcomeObservation, metadata: EventMetadata): OutcomeEvent;
