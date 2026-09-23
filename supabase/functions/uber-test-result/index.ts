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
  let body: unknown;
  try { body = await request.json(); } catch { return reply(400, { error: "invalid_json" }); }
  if (!body || typeof body !== "object" || Array.isArray(body)) return reply(400, { error: "invalid_request_shape" });
  const payload = body as Record<string, unknown>;
  if (typeof payload.offerId !== "string" || typeof payload.outcome !== "string" || typeof payload.idempotencyKey !== "string") return reply(400, { error: "result_fields_required" });
  const { data, error } = await client.rpc("record_uber_test_result", { p_offer_id: payload.offerId, p_outcome: payload.outcome, p_idempotency_key: payload.idempotencyKey });
  if (error) return reply(error.code === "42501" ? 403 : error.code === "23505" ? 409 : 422, { error: error.message });
  let evaluation: unknown = null;
  const nextOfferId = data?.next_offer_id;
  if (typeof nextOfferId === "string") {
    const evaluator = `${url}/functions/v1/uber-test-copilot-evaluate`;
    const response = await fetch(evaluator, { method: "POST", headers: { Authorization: authorization, apikey: anon, "Content-Type": "application/json" }, body: JSON.stringify({ offerId: nextOfferId, idempotencyKey: `uber-test-offer-${nextOfferId}` }) });
    evaluation = await response.json().catch(() => null);
  }
  return reply(201, { result: data, nextEvaluation: evaluation });
});
