import { createClient } from "@supabase/supabase-js";
import { doriCopilot } from "../_shared/dori-copilot-runtime.ts";

const headers = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type", "Content-Type": "application/json" };
const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return reply(401, { error: "authentication_required" });
  const url = Deno.env.get("SUPABASE_URL"); const anon = Deno.env.get("SUPABASE_ANON_KEY"); const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return reply(500, { error: "server_configuration_error" });
  const caller = createClient(url, anon, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: user, error: authError } = await caller.auth.getUser();
  if (authError || !user.user) return reply(401, { error: "invalid_access_token" });
  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return reply(400, { error: "invalid_json" }); }
  if (typeof body.batchId !== "string") return reply(400, { error: "batch_id_required" });
  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: dispatch, error: dispatchError } = await admin.from("uber_test_copilot_dispatches").select("id,batch_id,driver_profile_id,status,input_payload").eq("batch_id", body.batchId).maybeSingle();
  if (dispatchError) return reply(500, { error: "dispatch_lookup_failed" });
  if (!dispatch) return reply(200, { status: "ignored", reason: "turno_cerrado" });
  if (dispatch.status === "processed") return reply(200, { status: "duplicate", dispatchId: dispatch.id });
  const { data: driver, error: driverError } = await admin.from("driver_profiles").select("id,profile_id,environment_id,station_id").eq("id", dispatch.driver_profile_id).single();
  if (driverError || !driver) return reply(403, { error: "driver_not_found" });
  const payload = dispatch.input_payload as { offers?: Array<Record<string, unknown>> };
  const offers = Array.isArray(payload.offers) ? payload.offers : [];
  const now = new Date().toISOString();
  const results: unknown[] = [];
  for (const [index, offer] of offers.entries()) {
    const input = {
      trip: { fare: Number(offer.fare), pickupMinutes: 5, pickupKm: Number(offer.pickupDistanceKm), tripMinutes: Number(offer.tripDurationMinutes), tripKm: Number(offer.tripDistanceKm), origin: String(offer.pickup), destination: "TEST", timestamp: now, service: String(offer.service) },
      market: { now, hour: new Date().getHours(), weekday: ((new Date().getDay() + 6) % 7) + 1, originZone: "TEST", destinationZone: "TEST", demand: "normal", destinationValue: 85, nextWaitMinutes: 8, repositionKm: 1, repositionMinutes: 3, traffic: null, events: null, weather: null },
      vehicle: { vehicleId: `uber-test-${driver.id}`, batteryPercent: 80, rangeKm: 200, consumptionKwhPerKm: 0.16, energyCostPerKm: 0.6, odometerKm: 20000, distanceToStationKm: 3, destinationToStationKm: 8, requiredReturnAt: new Date(Date.now() + 8 * 3600000).toISOString() },
      driver: { driverId: driver.profile_id, shiftStart: new Date(Date.now() - 3600000).toISOString(), shiftEnd: new Date(Date.now() + 8 * 3600000).toISOString(), remainingMinutes: 480, connectedMinutes: 60, accumulatedIncome: 300, completedTrips: 3 },
      source: "simulated",
    };
    const event = doriCopilot.createDecisionEvent(input, { id: crypto.randomUUID(), createdAt: now });
    const { data: stored, error } = await admin.rpc("record_dori_decision_event", { p_auth_user_id: driver.profile_id, p_idempotency_key: `uber-test-${dispatch.batch_id}-${index + 1}`, p_event: event });
    if (error) return reply(error.code === "23505" ? 200 : 422, { error: error.message, partial: results });
    results.push(stored);
  }
  await admin.from("uber_test_copilot_dispatches").update({ status: "processed", processed_at: new Date().toISOString() }).eq("id", dispatch.id);
  return reply(201, { status: "processed", dispatchId: dispatch.id, decisions: results });
});
