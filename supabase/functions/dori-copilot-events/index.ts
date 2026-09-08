import { createClient } from "@supabase/supabase-js";
import {
  doriCopilot,
  type DecisionEvent,
  type DecisionInput,
  type OutcomeObservation,
} from "../_shared/dori-copilot-runtime.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };
const MAX_BODY_BYTES = 64 * 1024;

type DecisionRequest = { kind: "decision"; idempotencyKey: string; input: DecisionInput };
type OutcomeRequest = {
  kind: "outcome";
  idempotencyKey: string;
  decisionId: string;
  observation: OutcomeObservation;
};

class RequestError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

function response(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requireExactKeys(value: Record<string, unknown>, expected: string[]): void {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (actual.length !== wanted.length || actual.some((key, index) => key !== wanted[index])) {
    throw new RequestError(400, "invalid_request_shape");
  }
}

function parseRequest(value: unknown): DecisionRequest | OutcomeRequest {
  if (!isRecord(value)) throw new RequestError(400, "invalid_request_shape");
  const key = value.idempotencyKey;
  if (typeof key !== "string" || key.trim().length < 8 || key.trim().length > 200) {
    throw new RequestError(400, "invalid_idempotency_key");
  }
  if (value.kind === "decision") {
    requireExactKeys(value, ["kind", "idempotencyKey", "input"]);
    if (!isRecord(value.input)) throw new RequestError(400, "invalid_decision_input");
    return value as DecisionRequest;
  }
  if (value.kind === "outcome") {
    requireExactKeys(value, ["kind", "idempotencyKey", "decisionId", "observation"]);
    if (
      typeof value.decisionId !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value.decisionId) ||
      !isRecord(value.observation)
    ) throw new RequestError(400, "invalid_outcome_input");
    return value as OutcomeRequest;
  }
  throw new RequestError(400, "invalid_event_kind");
}

function mapDatabaseError(code?: string): RequestError {
  if (code === "42501") return new RequestError(403, "driver_identity_not_authorized");
  if (code === "P0002") return new RequestError(404, "decision_not_found");
  if (code === "23505") return new RequestError(409, "idempotency_key_conflict");
  if (code === "22023") return new RequestError(422, "event_validation_failed");
  return new RequestError(500, "persistence_failed");
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return response(405, { error: "method_not_allowed" });

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) throw new RequestError(401, "authentication_required");
    const contentLength = Number(request.headers.get("content-length") ?? 0);
    if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
      throw new RequestError(413, "request_too_large");
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      throw new RequestError(500, "server_configuration_error");
    }

    const rawBody = await request.text();
    if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) {
      throw new RequestError(413, "request_too_large");
    }
    let decoded: unknown;
    try {
      decoded = JSON.parse(rawBody);
    } catch {
      throw new RequestError(400, "invalid_json");
    }
    const payload = parseRequest(decoded);

    const caller = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await caller.auth.getUser();
    if (authError || !authData.user) throw new RequestError(401, "invalid_access_token");

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const metadata = { id: crypto.randomUUID(), createdAt: new Date().toISOString() };

    if (payload.kind === "decision") {
      let event;
      try {
        event = doriCopilot.createDecisionEvent(payload.input, metadata);
      } catch {
        throw new RequestError(422, "invalid_decision_input");
      }
      const { data, error } = await admin.rpc("record_dori_decision_event", {
        p_auth_user_id: authData.user.id,
        p_idempotency_key: payload.idempotencyKey.trim(),
        p_event: event,
      });
      if (error) throw mapDatabaseError(error.code);
      return response(201, { event: data });
    }

    const { data: stored, error: lookupError } = await admin
      .from("dori_decision_events")
      .select("event_payload")
      .eq("id", payload.decisionId)
      .maybeSingle();
    if (lookupError) throw new RequestError(500, "decision_lookup_failed");
    if (!stored) throw new RequestError(404, "decision_not_found");

    let outcome;
    try {
      outcome = doriCopilot.createOutcomeEvent(
        stored.event_payload as DecisionEvent,
        payload.observation,
        metadata,
      );
    } catch {
      throw new RequestError(422, "invalid_outcome_input");
    }
    const { data, error } = await admin.rpc("record_dori_outcome_event", {
      p_auth_user_id: authData.user.id,
      p_idempotency_key: payload.idempotencyKey.trim(),
      p_event: outcome,
    });
    if (error) throw mapDatabaseError(error.code);
    return response(201, { event: data });
  } catch (error) {
    if (error instanceof RequestError) return response(error.status, { error: error.message });
    console.error("dori-copilot-events failed", error);
    return response(500, { error: "internal_error" });
  }
});
