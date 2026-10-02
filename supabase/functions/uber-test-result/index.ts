import { createClient } from "npm:@supabase/supabase-js@2";

const headers = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Content-Type": "application/json" };
const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return reply(401, { error: "authentication_required" });
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anon) return reply(500, { error: "server_configuration_error" });
  const client = createClient(url, anon, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: user, error: authError } = await client.auth.getUser();
  if (authError || !user.user) return reply(401, { error: "invalid_access_token" });
  const installationId = request.headers.get("x-uber-test-installation-id")?.trim();
  if (!installationId) return reply(400, { error: "installation_id_required" });
  const { data: active, error: activeError } = await client.rpc("uber_test_assert_active_receiver", { p_installation_id: installationId });
  if (activeError || active !== true) return reply(403, { error: "uber_test_receiver_inactive" });
  let body: unknown;
  try { body = await request.json(); } catch { return reply(400, { error: "invalid_json" }); }
  if (!body || typeof body !== "object" || Array.isArray(body)) return reply(400, { error: "invalid_request_shape" });
  const payload = body as Record<string, unknown>;
  if (typeof payload.offerId !== "string" || typeof payload.outcome !== "string" || typeof payload.idempotencyKey !== "string" || typeof payload.occurredAt !== "string") return reply(400, { error: "result_fields_required" });
  if (!["accepted", "discarded", "expired"].includes(payload.outcome)) return reply(400, { error: "invalid_uber_test_outcome" });
  const observedAt = new Date(payload.occurredAt);
  if (Number.isNaN(observedAt.getTime())) return reply(400, { error: "invalid_occurred_at" });
  const rawObservation = payload.observation;
  let tripObservation: Record<string, number | null> | null = null;
  if (payload.outcome === "accepted") {
    if (!rawObservation || typeof rawObservation !== "object" || Array.isArray(rawObservation)) return reply(400, { error: "accepted_trip_observation_required" });
    const observation = rawObservation as Record<string, unknown>;
    for (const key of ["actualFare", "actualTripMinutes", "actualTripKm"] as const) {
      if (typeof observation[key] !== "number" || !Number.isFinite(observation[key]) || observation[key] <= 0) return reply(400, { error: "invalid_accepted_trip_observation" });
    }
    const optional = (key: "nextWaitMinutes" | "nextFare") => observation[key] == null ? null : typeof observation[key] === "number" && Number.isFinite(observation[key]) && observation[key] >= 0 ? observation[key] as number : NaN;
    const nextWaitMinutes = optional("nextWaitMinutes"); const nextFare = optional("nextFare");
    if (Number.isNaN(nextWaitMinutes) || Number.isNaN(nextFare)) return reply(400, { error: "invalid_accepted_trip_observation" });
    tripObservation = { actualFare: observation.actualFare as number, actualTripMinutes: observation.actualTripMinutes as number, actualTripKm: observation.actualTripKm as number, nextWaitMinutes, nextFare };
  }
  const { data, error } = await client.rpc("record_uber_test_result", { p_offer_id: payload.offerId, p_outcome: payload.outcome, p_idempotency_key: payload.idempotencyKey });
  if (error) return reply(error.code === "42501" ? 403 : error.code === "23505" ? 409 : 422, { error: error.message });

  const [{ data: decision, error: decisionError }, { data: offerEvent, error: eventError }] = await Promise.all([
    client.from("dori_decision_events").select("id").eq("offer_id", payload.offerId).maybeSingle(),
    client.from("uber_test_offer_events").select("copilot_status").eq("presented_offer_id", payload.offerId).maybeSingle(),
  ]);
  if (decisionError || eventError || !offerEvent) return reply(503, { error: "copilot_outcome_lookup_pending" });
  if (!decision && ["pending", "evaluated"].includes(offerEvent.copilot_status)) return reply(503, { error: "copilot_decision_not_visible_yet" });

  let copilotOutcome: unknown = null;
  if (decision?.id) {
    const driverAction = payload.outcome === "accepted" ? "accepted" : payload.outcome === "discarded" ? "rejected" : "unknown";
    const observation = {
      observedAt: observedAt.toISOString(),
      driverAction,
      actualFare: payload.outcome === "accepted" ? tripObservation?.actualFare ?? null : null,
      actualTripMinutes: payload.outcome === "accepted" ? tripObservation?.actualTripMinutes ?? null : null,
      actualTripKm: payload.outcome === "accepted" ? tripObservation?.actualTripKm ?? null : null,
      nextWaitMinutes: payload.outcome === "accepted" ? tripObservation?.nextWaitMinutes ?? null : null,
      nextFare: payload.outcome === "accepted" ? tripObservation?.nextFare ?? null : null,
    };
    const outcomeResponse = await fetch(`${url}/functions/v1/dori-copilot-events`, {
      method: "POST",
      headers: { Authorization: authorization, apikey: anon, "Content-Type": "application/json" },
      body: JSON.stringify({
        kind: "outcome",
        idempotencyKey: `uber-test-outcome-${payload.offerId}-${payload.outcome}`,
        decisionId: decision.id,
        observation,
      }),
    });
    copilotOutcome = await outcomeResponse.json().catch(() => null);
    if (!outcomeResponse.ok) return reply(503, { error: "copilot_outcome_sync_pending", detail: copilotOutcome });
  }

  let evaluation: unknown = null;
  const nextOfferId = data?.next_offer_id;
  if (typeof nextOfferId === "string") {
    const evaluator = `${url}/functions/v1/uber-test-copilot-evaluate`;
    const response = await fetch(evaluator, { method: "POST", headers: { Authorization: authorization, apikey: anon, "Content-Type": "application/json" }, body: JSON.stringify({ offerId: nextOfferId, idempotencyKey: `uber-test-offer-${nextOfferId}` }) });
    evaluation = await response.json().catch(() => null);
  }
  return reply(201, { result: data, copilotOutcome, nextEvaluation: evaluation });
});
