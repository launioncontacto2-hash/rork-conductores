import { createClient } from "@supabase/supabase-js";
import { doriCopilot } from "../_shared/dori-copilot-runtime.ts";

const headers = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type", "Content-Type": "application/json" };
const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers });
const record = (x: unknown): x is Record<string, unknown> => !!x && typeof x === "object" && !Array.isArray(x);

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return reply(401, { error: "authentication_required" });
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return reply(500, { error: "server_configuration_error" });
  const caller = createClient(url, anon, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await caller.auth.getUser();
  if (authError || !authData.user) return reply(401, { error: "invalid_access_token" });
  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  let payload: unknown;
  try { payload = await request.json(); } catch { return reply(400, { error: "invalid_json" }); }
  if (!record(payload) || typeof payload.operation !== "string") return reply(400, { error: "invalid_request_shape" });
  const authUserId = authData.user.id;
  if (payload.operation === "create") {
    if (typeof payload.idempotencyKey !== "string" || typeof payload.testCaseId !== "string" || typeof payload.driverProfileId !== "string" || typeof payload.expiresAt !== "string" || !record(payload.input) || !record(payload.expected)) return reply(400, { error: "create_fields_required" });
    const expected = payload.expected;
    if (expected.recommendation !== "RECOMENDADO" && expected.recommendation !== "NO RECOMENDADO") return reply(422, { error: "invalid_expected_recommendation" });
    const { data, error } = await admin.rpc("console_create_dori_simulation_case", {
      p_auth_user_id: authUserId, p_idempotency_key: payload.idempotencyKey, p_test_case_id: payload.testCaseId,
      p_driver_profile_id: payload.driverProfileId, p_input_payload: payload.input,
      p_expected_recommendation: expected.recommendation, p_expected_reason_code: expected.reasonCode ?? null,
      p_criterion_version: expected.criterionVersion ?? "lab-1.0.0", p_expires_at: payload.expiresAt,
    });
    if (error) return reply(error.code === "42501" ? 403 : error.code === "23505" ? 409 : 422, { error: error.message });
    return reply(201, { case: data });
  }
  if (payload.operation === "next") {
    const rpc = typeof payload.caseId === "string" ? "driver_get_dori_simulation_case" : "driver_next_dori_simulation_case";
    const args = typeof payload.caseId === "string" ? { p_auth_user_id: authUserId, p_case_id: payload.caseId } : { p_auth_user_id: authUserId };
    const { data, error } = await admin.rpc(rpc, args);
    if (error) {
      if (error.code === "42883") return reply(503, { error: "simulation_backend_unavailable" });
      if (error.code === "42501") return reply(403, { error: "case_not_available" });
      return reply(500, { error: "simulation_backend_error" });
    }
    return reply(200, { case: data });
  }
  if (payload.operation === "evaluate") {
    if (typeof payload.caseId !== "string" || typeof payload.idempotencyKey !== "string") return reply(400, { error: "evaluation_fields_required" });
    const { data: existing, error: existingError } = await admin.rpc("driver_get_dori_simulation_evaluation", { p_auth_user_id: authUserId, p_case_id: payload.caseId, p_idempotency_key: payload.idempotencyKey });
    if (existingError) {
      if (existingError.code === "42883") return reply(503, { error: "simulation_backend_unavailable" });
      if (existingError.code === "42501") return reply(403, { error: "case_not_available" });
      return reply(500, { error: "simulation_backend_error" });
    }
    if (existing) return reply(201, { evaluation: existing });
    const { data: pending, error: loadError } = await admin.rpc("driver_get_dori_simulation_case", { p_auth_user_id: authUserId, p_case_id: payload.caseId });
    if (loadError) {
      if (loadError.code === "42883") return reply(503, { error: "simulation_backend_unavailable" });
      if (loadError.code === "42501") return reply(403, { error: "case_not_available" });
      return reply(500, { error: "simulation_backend_error" });
    }
    if (!pending?.input_payload) return reply(404, { error: "case_not_available" });
    let result;
    try { result = doriCopilot.evaluate(pending.input_payload); } catch { return reply(422, { error: "invalid_simulation_input" }); }
    const { data, error } = await admin.rpc("record_dori_simulation_evaluation", { p_auth_user_id: authUserId, p_case_id: payload.caseId, p_idempotency_key: payload.idempotencyKey, p_result_payload: result });
    if (error) return reply(error.code === "22023" ? 422 : 409, { error: error.message });
    return reply(201, { evaluation: data });
  }
  return reply(400, { error: "unsupported_operation" });
});
