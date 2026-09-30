import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";
const headers = { "content-type": "application/json", "access-control-allow-origin": "*" };
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
const EXPECTED_AGENT_TOKEN_SHA256 = "__DORI_AGENT_TOKEN_SHA256__";
const sha256Hex = async (value: string) => {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
};
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: { ...headers, "access-control-allow-methods": "POST", "access-control-allow-headers": "content-type, x-dori-agent-token" } });
  if (req.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  const token = req.headers.get("x-dori-agent-token");
  if (!token || EXPECTED_AGENT_TOKEN_SHA256 === "__DORI_AGENT_TOKEN_SHA256__" || await sha256Hex(token) !== EXPECTED_AGENT_TOKEN_SHA256) return reply({ error: "unauthorized" }, 401);
  const body = await req.json().catch(() => null) as Record<string, unknown> | null;
  if (!body || body.vehicle_code !== "DMP-003") return reply({ error: "vehicle_not_allowed" }, 403);
  const soc = Number(body.soc_percent), odo = Number(body.odometer_km), sequence = Number(body.sequence);
  const captured = new Date(String(body.captured_at));
  if (!Number.isFinite(soc) || soc < 0 || soc > 100 || !Number.isFinite(odo) || odo < 0 || !Number.isSafeInteger(sequence) || sequence < 0 || Number.isNaN(captured.getTime())) return reply({ error: "invalid_payload" }, 422);
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: vehicle } = await db.from("vehicles").select("id,environment_id,station_id,odometer_km").eq("operational_code", "DMP-003").maybeSingle();
  if (!vehicle) return reply({ error: "vehicle_not_found" }, 404);
  const powerState = body.power_state == null ? null : Number(body.power_state);
  if (powerState !== null && (!Number.isInteger(powerState) || powerState < 0 || powerState > 3)) return reply({ error: "invalid_power_state" }, 422);
  const { data: current } = await db.from("vehicle_telemetry_latest").select("sequence,odometer_km,soc_percent,power_state,captured_at,agent_version,source").eq("vehicle_id", vehicle.id).maybeSingle();
  if (current && sequence < current.sequence) return reply({ error: "sequence_rejected" }, 409);
  if (current && sequence === current.sequence) {
    const identical = Number(current.soc_percent) === soc && Number(current.odometer_km) === odo && (current.power_state == null ? powerState === null : Number(current.power_state) === powerState) && String(current.captured_at) === captured.toISOString() && String(current.agent_version) === String(body.agent_version ?? "0.8") && current.source === "dori_vehicle_agent";
    return identical ? reply({ accepted: true, idempotent: true, vehicle_id: vehicle.id, sequence }) : reply({ error: "sequence_conflict" }, 409);
  }
  if (current && odo < Number(current.odometer_km)) return reply({ error: "odometer_rejected" }, 409);
  const received = new Date().toISOString();
  const snapshot = { vehicle_id: vehicle.id, environment_id: vehicle.environment_id, station_id: vehicle.station_id, soc_percent: soc, odometer_km: odo, power_state: powerState, captured_at: captured.toISOString(), received_at: received, agent_version: String(body.agent_version ?? "0.8"), sequence, source: "dori_vehicle_agent" };
  const { error } = await db.from("vehicle_telemetry_latest").upsert(snapshot, { onConflict: "vehicle_id" });
  if (error) return reply({ error: "snapshot_failed" }, 500);
  const { error: syncError } = await db.from("vehicles").update({ odometer_km: Math.round(odo), battery_pct: Math.round(soc) }).eq("id", vehicle.id);
  if (syncError) return reply({ error: "vehicle_sync_failed" }, 500);
  return reply({ accepted: true, vehicle_id: vehicle.id, received_at: received, sequence });
});
