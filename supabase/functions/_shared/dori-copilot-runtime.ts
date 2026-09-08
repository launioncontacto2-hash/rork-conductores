import "./dori-copilot.js";

import type {
  DecisionEvent,
  DecisionInput,
  EventMetadata,
  OutcomeEvent,
  OutcomeObservation,
} from "./dori-copilot.d.ts";

type DoriCopilotRuntime = {
  createDecisionEvent(input: DecisionInput, metadata: EventMetadata): DecisionEvent;
  createOutcomeEvent(decision: DecisionEvent, observation: OutcomeObservation, metadata: EventMetadata): OutcomeEvent;
};

const runtime = (globalThis as typeof globalThis & { DoriCopilot?: DoriCopilotRuntime }).DoriCopilot;
if (!runtime) throw new Error("dori_copilot_runtime_unavailable");

export const doriCopilot = runtime;
export type { DecisionEvent, DecisionInput, OutcomeEvent, OutcomeObservation };
