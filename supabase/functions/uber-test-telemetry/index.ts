import { createClient } from "npm:@supabase/supabase-js@2.115.0";

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
  let payload: Record<string, unknown>;
  try { payload = await request.json(); } catch { return reply(400, { error: "invalid_json" }); }
  const required = ["installationId", "appBuild", "sessionGeneration", "eventName"];
  if (required.some((key) => typeof payload[key] !== "string" || !(payload[key] as string).trim())) return reply(400, { error: "telemetry_fields_required" });
  const { data, error } = await client.rpc("record_uber_test_transport_event", {
    p_installation_id: payload.installationId,
    p_app_build: payload.appBuild,
    p_session_generation: payload.sessionGeneration,
    p_event_name: payload.eventName,
    p_event_at: typeof payload.eventAt === "string" ? payload.eventAt : new Date().toISOString(),
    p_batch_id: typeof payload.batchId === "string" ? payload.batchId : null,
    p_transport: typeof payload.transport === "string" ? payload.transport : null,
    p_metadata: payload.metadata && typeof payload.metadata === "object" ? payload.metadata : {},
  });
  if (error) return reply(error.code === "42501" ? 403 : 422, { error: error.message });
  return reply(201, { id: data });
});
