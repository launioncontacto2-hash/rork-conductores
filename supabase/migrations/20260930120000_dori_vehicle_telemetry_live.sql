CREATE TABLE IF NOT EXISTS public.vehicle_telemetry_latest (
  vehicle_id uuid PRIMARY KEY REFERENCES public.vehicles(id) ON DELETE CASCADE,
  environment_id uuid NOT NULL,
  station_id uuid NOT NULL,
  soc_percent numeric NOT NULL CHECK (soc_percent >= 0 AND soc_percent <= 100),
  odometer_km numeric NOT NULL CHECK (odometer_km >= 0),
  power_state integer,
  captured_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  agent_version text NOT NULL,
  sequence bigint NOT NULL CHECK (sequence >= 0),
  source text NOT NULL DEFAULT 'dori_vehicle_agent',
  FOREIGN KEY (vehicle_id, station_id, environment_id)
    REFERENCES public.vehicles(id, station_id, environment_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS vehicle_telemetry_latest_freshness_idx
  ON public.vehicle_telemetry_latest(received_at DESC);
ALTER TABLE public.vehicle_telemetry_latest ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.vehicle_telemetry_latest FROM anon, authenticated;
GRANT SELECT ON public.vehicle_telemetry_latest TO authenticated;
GRANT ALL ON public.vehicle_telemetry_latest TO service_role, postgres;
CREATE POLICY vehicle_telemetry_driver_read ON public.vehicle_telemetry_latest
  FOR SELECT TO authenticated USING (EXISTS (
    SELECT 1 FROM public.assignments a
    JOIN public.driver_profiles dp ON dp.id = a.driver_profile_id
    WHERE a.vehicle_id = vehicle_telemetry_latest.vehicle_id
      AND a.ended_at IS NULL AND dp.profile_id = app.auth_profile_id()
  ));
CREATE POLICY vehicle_telemetry_station_read ON public.vehicle_telemetry_latest
  FOR SELECT TO authenticated USING (station_id IN (SELECT station_id FROM app.auth_station_ids()));
