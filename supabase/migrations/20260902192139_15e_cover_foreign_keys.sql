-- Indices que cubren por completo las claves foraneas de 15E.
-- Los indices de lectura por fecha se conservan porque atienden consultas
-- distintas: tableros por estacion, conductor, vehiculo y orden.

CREATE INDEX incidents_reporter_environment_idx
    ON public.incidents(reported_by, environment_id);
CREATE INDEX incidents_shift_scope_idx
    ON public.incidents(shift_id, station_id, environment_id);
CREATE INDEX incidents_vehicle_scope_idx
    ON public.incidents(vehicle_id, station_id, environment_id);

CREATE INDEX work_orders_incident_scope_idx
    ON public.work_orders(incident_id, station_id, environment_id);
CREATE INDEX work_orders_vehicle_scope_idx
    ON public.work_orders(vehicle_id, station_id, environment_id);
CREATE INDEX work_orders_opener_environment_idx
    ON public.work_orders(opened_by, environment_id);
CREATE INDEX work_orders_technician_environment_idx
    ON public.work_orders(technician_profile_id, environment_id);

CREATE INDEX work_order_updates_order_scope_idx
    ON public.work_order_updates(work_order_id, station_id, environment_id);
CREATE INDEX work_order_updates_actor_environment_idx
    ON public.work_order_updates(actor_profile_id, environment_id);
