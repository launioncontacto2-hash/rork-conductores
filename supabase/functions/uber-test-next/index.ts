import { createClient } from "npm:@supabase/supabase-js@2";
const headers = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Content-Type": "application/json" };
const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers });
Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return reply(401, { error: "authentication_required" });
  const url = Deno.env.get("SUPABASE_URL"); const anon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anon) return reply(500, { error: "server_configuration_error" });
  const client = createClient(url, anon, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: user, error: authError } = await client.auth.getUser();
  if (authError || !user.user) return reply(401, { error: "invalid_access_token" });
  const installationId = request.headers.get("x-uber-test-installation-id")?.trim();
  if (!installationId) return reply(400, { error: "installation_id_required" });
  const { data: active, error: activeError } = await client.rpc("uber_test_assert_active_receiver", { p_installation_id: installationId });
  if (activeError || active !== true) return reply(403, { error: "uber_test_receiver_inactive" });
  const { data, error } = await client.rpc("driver_get_uber_test_batch", { p_installation_id: installationId });
  if (error) return reply(error.code === "42501" ? 403 : 500, { error: error.message });
  if (!data) return reply(200, { batch: null });
  const { data: presented, error: presentError } = await client.rpc("present_next_uber_test_offer", { p_batch_id: data.id });
  if (presentError) return reply(presentError.code === "42501" ? 403 : 500, { error: presentError.message });
  let evaluation: unknown = null;
  if (presented?.offer?.id) {
    const evaluator = `${url}/functions/v1/uber-test-copilot-evaluate`;
    const response = await fetch(evaluator, { method: "POST", headers: { Authorization: authorization, apikey: anon, "Content-Type": "application/json" }, body: JSON.stringify({ offerId: presented.offer.id, idempotencyKey: `uber-test-offer-${presented.offer.id}` }) });
    evaluation = await response.json().catch(() => null);
  }
  return reply(200, { batch: { ...data, presented: presented?.offer ?? null, presentationStatus: presented?.status ?? null, evaluation } });
});
