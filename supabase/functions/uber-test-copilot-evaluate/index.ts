import { createClient } from "npm:@supabase/supabase-js@2.115.0";
import { doriCopilot } from "../_shared/dori-copilot-runtime.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json(401, { error: "authentication_required" });
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !serviceRole) return json(500, { error: "server_configuration_error" });
  const caller = createClient(url, anon, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await caller.auth.getUser();
  if (authError || !authData.user) return json(401, { error: "invalid_access_token" });
  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return json(400, { error: "invalid_json" }); }
  if (typeof body.offerId !== "string" || typeof body.idempotencyKey !== "string") return json(400, { error: "offer_id_and_idempotency_key_required" });
  const admin = createClient(url, serviceRole, { auth: { persistSession: false, autoRefreshToken: false } });
  // Resolve with the caller's JWT so app.auth_profile_id() remains the
  // conductor identity. The service client is reserved for backend writes.
  const { data: context, error: contextError } = await caller.rpc("resolve_uber_test_dori_context", { p_offer_id: body.offerId });
  if (contextError) return json(contextError.code === "PGRST116" ? 404 : 422, { error: "context_resolution_failed" });
  if (!context || context.status !== "ready") return json(200, { status: context?.status ?? "context_missing", reason: context?.reason ?? null, offerId: body.offerId });
  const input = context.input;
  let event: Record<string, unknown>;
  try {
    const canonical = doriCopilot.createDecisionEvent(input, { id: crypto.randomUUID(), createdAt: new Date().toISOString() }) as unknown as Record<string, unknown>;
    event = { ...canonical, offerId: body.offerId };
  }
  catch { return json(422, { error: "invalid_decision_input" }); }
  const { data: stored, error: persistError } = await admin.rpc("record_dori_decision_event", { p_auth_user_id: authData.user.id, p_idempotency_key: body.idempotencyKey, p_event: event });
  if (persistError) return json(persistError.code === "42501" ? 403 : persistError.code === "23505" ? 409 : 422, { error: "evaluation_persistence_failed" });
  await admin.from("uber_test_offer_events").update({ copilot_status: "evaluated" }).eq("presented_offer_id", body.offerId);
  const trip = input.trip as { fare: number; pickupKm: number; tripKm: number; pickupMinutes: number; tripMinutes: number };
  const result = event.result as Record<string, unknown>;
  const recommendation = result.recommendation as string;
  const effectivePerKm = trip.fare / (trip.pickupKm + trip.tripKm);
  const effectivePerHour = trip.fare / ((trip.pickupMinutes + trip.tripMinutes) / 60);
  const bodyText = `${recommendation === "RECOMENDADO" ? "TOMAR" : "NO TOMAR"} · $${effectivePerKm.toFixed(2)}/km · $${effectivePerHour.toFixed(0)}/h`;
  const { data: existingNotification, error: existingNotificationError } = await admin.from("dori_copilot_notifications").select("id,status").eq("offer_id", body.offerId).maybeSingle();\n  if (existingNotificationError) return json(500, { error: "notification_lookup_failed" });\n  let notificationStatus = existingNotification?.status ?? "pending";\n  let notificationError = null;\n  if (!existingNotification) {\n    const inserted = await admin.from("dori_copilot_notifications").insert({ environment_id: context.environment_id, profile_id: input.driver.driverId, offer_id: body.offerId, recommendation, body: bodyText, payload: { offerId: body.offerId, recommendation, reasons: result.reasons, effectivePerKm, effectivePerHour }, status: "pending" });\n    notificationError = inserted.error;\n  }
  if (notificationError) return json(500, { error: "notification_enqueue_failed" });
  let notificationDispatch = "pending";
  const dispatchSecret = Deno.env.get("PUSH_DISPATCH_SECRET");
  if (dispatchSecret) {
    const dispatchResponse = await fetch(`${url}/functions/v1/dori-copilot-push`, {
      method: "POST",
      headers: { Authorization: authorization, apikey: anon, "x-push-dispatch-secret": dispatchSecret },
    });
    notificationDispatch = dispatchResponse.ok ? "attempted" : "pending";
  }
  return json(201, { status: "evaluated", offerId: body.offerId, event: stored, recommendation, reasons: result.reasons, effectivePerKm, effectivePerHour, notification: notificationStatus, notificationDispatch });
});
