BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(17);

SELECT has_column('public', 'vehicles', 'manufacturer', 'vehiculo conserva fabricante');
SELECT has_column('public', 'vehicles', 'model_display', 'vehiculo tiene nombre corto de interfaz');
SELECT has_column('public', 'vehicles', 'unit_number', 'vehiculo tiene numero visible');
SELECT has_column('public', 'vehicles', 'operational_code', 'vehiculo tiene codigo operativo');
SELECT has_column('public', 'vehicles', 'color', 'vehiculo admite color separado');
SELECT has_column('public', 'console_drivers', 'display_name', 'consola recibe el nombre humano del conductor');

INSERT INTO public.regions (id, environment_id, code, name, status)
SELECT
    'd0010000-0000-4000-8000-000000000001'::uuid,
    id,
    'dori-unit-test-region',
    'DORI Unit Test Region',
    'active'
FROM public.environments
WHERE code = 'test';

INSERT INTO public.stations (id, environment_id, region_id, code, name, status)
SELECT
    'd0020000-0000-4000-8000-000000000001'::uuid,
    environment_id,
    id,
    'dori-unit-test-station',
    'DORI Unit Test Station',
    'active'
FROM public.regions
WHERE id = 'd0010000-0000-4000-8000-000000000001'::uuid;

INSERT INTO public.vehicles (
    id, environment_id, station_id, internal_number, qr_code, model, status
)
SELECT
    'd0030000-0000-4000-8000-000000000001'::uuid,
    environment_id,
    id,
    'LAB-15C-001',
    'DORI-UNIT-TEST-QR',
    'Turno EV Laboratorio',
    'occupied'
FROM public.stations
WHERE id = 'd0020000-0000-4000-8000-000000000001'::uuid;

SELECT app.apply_dori_test_vehicle_identity();

SELECT is((SELECT manufacturer FROM public.vehicles WHERE internal_number = 'LAB-15C-001'), 'BYD', 'unidad TEST mapea fabricante BYD');
SELECT is((SELECT model FROM public.vehicles WHERE internal_number = 'LAB-15C-001'), 'Dolphin Mini Plus', 'model conserva nombre maestro');
SELECT is((SELECT model_display FROM public.vehicles WHERE internal_number = 'LAB-15C-001'), 'Dolphin Mini P.', 'unidad TEST tiene nombre corto');
SELECT is((SELECT unit_number FROM public.vehicles WHERE internal_number = 'LAB-15C-001'), 1, 'unidad TEST tiene numero 001');
SELECT is((SELECT operational_code FROM public.vehicles WHERE internal_number = 'LAB-15C-001'), 'DMP-001', 'unidad TEST tiene codigo DMP-001');
SELECT is((SELECT color FROM public.vehicles WHERE internal_number = 'LAB-15C-001'), NULL::text, 'no se inventa color ausente');
SELECT is((SELECT internal_number FROM public.vehicles WHERE operational_code = 'DMP-001'), 'LAB-15C-001', 'referencia tecnica TEST se conserva');

SELECT throws_ok(
    $sql$ UPDATE public.vehicles SET unit_number = 0 WHERE internal_number = 'LAB-15C-001' $sql$,
    '23514',
    NULL,
    'numero operativo invalido se rechaza'
);
SELECT throws_ok(
    $sql$ UPDATE public.vehicles SET operational_code = '' WHERE internal_number = 'LAB-15C-001' $sql$,
    '23514',
    NULL,
    'codigo operativo vacio se rechaza'
);
SELECT throws_ok(
    $sql$ UPDATE public.vehicles SET color = '' WHERE internal_number = 'LAB-15C-001' $sql$,
    '23514',
    NULL,
    'color vacio se rechaza; ausencia se representa con NULL'
);
SELECT is(
    (SELECT count(*)::integer FROM public.vehicles WHERE internal_number = 'LAB-15C-001'),
    1,
    'mapeo TEST conserva una sola fila y el mismo vehicle_id'
);

SELECT * FROM finish();
ROLLBACK;
