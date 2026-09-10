import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { vi } from "vitest";
import { render } from "vitest-browser-react";

const rpcCalls = vi.hoisted(() => [] as Array<{ name: string; params: Record<string, unknown> }>);
const signedURLCalls = vi.hoisted(() => [] as Array<{ paths: string[]; expiresIn: number }>);

const identity = {
  profile_id: "10000000-0000-4000-8000-000000000001",
  environment_id: "00000000-0000-4000-8000-000000000001",
  display_name: "Supervisión DORI",
  employee_number: "SUP-001",
  membership_id: "20000000-0000-4000-8000-000000000001",
  station_id: "30000000-0000-4000-8000-000000000001",
  role: "supervisor" as const,
  station_code: "PUE-TEST-01",
  station_name: "Puebla Laboratorio 01",
  station_timezone: "America/Mexico_City",
};

vi.mock("@/console/ConsoleAuth", () => ({
  useConsoleAuth: () => ({
    identity,
    realtimeConnections: 2,
    refreshIdentity: async () => identity,
    signOut: async () => undefined,
  }),
}));

const tableData: Record<string, unknown> = {
  station_live: { active_shifts: 0, present_drivers: 0, available_units: 2, units_in_shop: 0, updated_at: "2026-09-07T12:00:00Z" },
  test_clock: null,
  station_capacity_current: { capacity: 20 },
  vehicles: [],
  console_drivers: [],
  assignment_current: [],
  shifts: [],
  shift_evidence: [],
  devices: [],
  incidents: [],
  work_orders: [],
  absences: [],
  coverage_vacancies: [],
  audit_history: [{
    id: "60000000-0000-4000-8000-000000000001",
    station_id: identity.station_id,
    actor_profile_id: identity.profile_id,
    actor_name: "Supervisión DORI",
    actor_employee_number: "SUP-001",
    event_type: "assignment.created",
    entity_type: "assignment",
    entity_id: "70000000-0000-4000-8000-000000000001",
    metadata: {},
    occurred_at: "2026-09-07T12:00:00Z",
  }],
};

const queryFor = (table: string) => {
  const result = { data: tableData[table] ?? [], error: null };
  const query = {
    select: () => query,
    eq: () => query,
    order: () => query,
    limit: () => query,
    maybeSingle: async () => result,
    then: (resolve: (value: typeof result) => unknown) => Promise.resolve(result).then(resolve),
  };
  return query;
};

vi.mock("@/lib/supabase", () => ({
  supabase: {
    from: (table: string) => queryFor(table),
    rpc: async (name: string, params: Record<string, unknown>) => {
      if (name === "console_audit_history") return { data: tableData.audit_history, error: null };
      rpcCalls.push({ name, params });
      return { data: null, error: null };
    },
    storage: {
      from: () => ({
        createSignedUrls: async (paths: string[], expiresIn: number) => {
          signedURLCalls.push({ paths, expiresIn });
          return {
            data: paths.map((path) => ({ path, signedUrl: `https://evidence.test/${path}` })),
            error: null,
          };
        },
      }),
    },
  },
}));

import OperationsConsole from "@/pages/OperationsConsole";

test("shows every final operational area from one Supabase snapshot", async () => {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const screen = await render(
    <QueryClientProvider client={client}>
      <OperationsConsole />
    </QueryClientProvider>,
  );

  await expect.element(screen.getByRole("heading", { name: "Consola DORI" })).toBeInTheDocument();
  await expect.element(screen.getByRole("navigation", { name: "Secciones de Consola DORI" })).toBeInTheDocument();
  await expect.element(screen.getByRole("heading", { name: "Asignar unidad" })).toBeInTheDocument();
  await expect.element(screen.getByText("Operación protegida")).toBeInTheDocument();
  await expect.element(screen.getByRole("heading", { name: "Incidencias" })).toBeInTheDocument();
  await expect.element(screen.getByRole("heading", { name: "Taller" })).toBeInTheDocument();
  await expect.element(screen.getByRole("heading", { name: "Ausencias" })).toBeInTheDocument();
  await expect.element(screen.getByRole("heading", { name: "Vacantes de cobertura" })).toBeInTheDocument();
  await expect.element(screen.getByRole("heading", { name: "Historial de turnos" })).toBeInTheDocument();
  await expect.element(screen.getByRole("heading", { name: "Auditoría operativa" })).toBeInTheDocument();
  await expect.element(screen.getByText("Unidad asignada")).toBeInTheDocument();
});

test("requires an audit reason before receiving an incident", async () => {
  rpcCalls.length = 0;
  tableData.incidents = [{
    id: "40000000-0000-4000-8000-000000000001",
    folio: "INC-DORI-001",
    vehicle_id: "50000000-0000-4000-8000-000000000001",
    kind: "mechanical",
    severity: "high",
    description: "La unidad perdió potencia durante el turno.",
    status: "open",
    revision: 1,
    reported_at: "2026-09-07T12:00:00Z",
  }];

  try {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const screen = await render(
      <QueryClientProvider client={client}>
        <OperationsConsole />
      </QueryClientProvider>,
    );

    await screen.getByRole("button", { name: "Recibir" }).click();
    const confirm = screen.getByRole("button", { name: "Confirmar y auditar" });
    await expect.element(confirm).toBeDisabled();
    await screen.getByRole("textbox", { name: "Motivo obligatorio" }).fill("Recepción confirmada por supervisión");
    await expect.element(confirm).toBeEnabled();
    await confirm.click();

    await vi.waitFor(() => {
      expect(rpcCalls).toHaveLength(1);
      expect(rpcCalls[0]).toMatchObject({
        name: "update_incident",
        params: {
          p_incident_id: "40000000-0000-4000-8000-000000000001",
          p_expected_revision: 1,
          p_status: "review",
          p_note: "Recepción confirmada por supervisión",
        },
      });
      expect(String(rpcCalls[0].params.p_idempotency_key)).toMatch(/^console-review-incident-/);
    });
  } finally {
    tableData.incidents = [];
  }
});

test("revokes only a visible driver device with an audited reason", async () => {
  rpcCalls.length = 0;
  tableData.console_drivers = [{
    id: "71000000-0000-4000-8000-000000000001",
    profile_id: "72000000-0000-4000-8000-000000000001",
    display_name: "Conductor TEST 001",
    employee_number: "DRV-DORI-001",
    status: "active",
    shift_group: "weekday",
    shift_slot: "morning",
  }];
  tableData.devices = [{
    id: "73000000-0000-4000-8000-000000000001",
    profile_id: "72000000-0000-4000-8000-000000000001",
    platform: "ios",
    app_version: "dori-1.0",
    last_seen_at: new Date().toISOString(),
  }];

  try {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const screen = await render(
      <QueryClientProvider client={client}>
        <OperationsConsole />
      </QueryClientProvider>,
    );

    await screen.getByRole("button", { name: "Retirar acceso" }).click();
    const confirm = screen.getByRole("button", { name: "Confirmar y auditar" });
    await expect.element(confirm).toBeDisabled();
    await screen.getByRole("textbox", { name: "Motivo obligatorio" }).fill("iPhone reportado como extraviado");
    await expect.element(confirm).toBeEnabled();
    await confirm.click();

    await vi.waitFor(() => {
      expect(rpcCalls).toHaveLength(1);
      expect(rpcCalls[0]).toMatchObject({
        name: "revoke_driver_device",
        params: {
          p_device_id: "73000000-0000-4000-8000-000000000001",
          p_note: "iPhone reportado como extraviado",
        },
      });
      expect(String(rpcCalls[0].params.p_idempotency_key)).toMatch(/^console-revoke-driver-device-/);
    });
  } finally {
    tableData.console_drivers = [];
    tableData.devices = [];
  }
});

test("shows the operational DORI unit identity and keeps the TEST code secondary", async () => {
  tableData.vehicles = [{
    id: "83000000-0000-4000-8000-000000000001",
    internal_number: "LAB-15C-001",
    plate: null,
    model: "Dolphin Mini Plus",
    manufacturer: "BYD",
    model_display: "Dolphin Mini P.",
    unit_number: 1,
    operational_code: "DMP-001",
    color: null,
    battery_pct: 80,
    odometer_km: 40,
    status: "occupied",
  }];
  tableData.console_drivers = [{
    id: "71000000-0000-4000-8000-000000000001",
    profile_id: "72000000-0000-4000-8000-000000000001",
    display_name: "Conductor TEST 001",
    employee_number: "DRV-TEST-001",
    status: "active",
    shift_group: "weekday",
    shift_slot: "morning",
  }];
  tableData.assignment_current = [{
    driver_profile_id: "71000000-0000-4000-8000-000000000001",
    vehicle_id: "83000000-0000-4000-8000-000000000001",
    kind: "titular",
    titular_vehicle_id: null,
    assigned_at: "2026-09-07T11:00:00Z",
  }];

  try {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const screen = await render(
      <QueryClientProvider client={client}>
        <OperationsConsole />
      </QueryClientProvider>,
    );

    await expect.element(screen.getByText("Unidad 001")).toBeInTheDocument();
    await expect.element(screen.getByText("Dolphin Mini P.")).toBeInTheDocument();
    await expect.element(screen.getByText("Color no registrado")).toBeInTheDocument();
    await expect.element(screen.getByText("DMP-001")).toBeInTheDocument();
    await expect.element(screen.getByRole("cell", { name: "Conductor TEST 001" })).toBeInTheDocument();
  } finally {
    tableData.vehicles = [];
    tableData.console_drivers = [];
    tableData.assignment_current = [];
  }
});

test("opens private shift evidence through short-lived signed URLs", async () => {
  signedURLCalls.length = 0;
  tableData.shifts = [{
    id: "81000000-0000-4000-8000-000000000001",
    folio: "TUR-DORI-001",
    driver_profile_id: "82000000-0000-4000-8000-000000000001",
    vehicle_id: "83000000-0000-4000-8000-000000000001",
    started_at: "2026-09-07T11:00:00Z",
    scheduled_end_at: "2026-09-07T20:00:00Z",
    finished_at: "2026-09-07T20:00:00Z",
    end_odometer_km: 12345,
    end_battery_pct: 40,
  }];
  tableData.shift_evidence = [
    {
      id: "84000000-0000-4000-8000-000000000001",
      shift_id: "81000000-0000-4000-8000-000000000001",
      kind: "start_odometer",
      object_path: "test/station/driver/operation/start-odometer.jpg",
      captured_at: "2026-09-07T11:00:00Z",
    },
    {
      id: "84000000-0000-4000-8000-000000000002",
      shift_id: "81000000-0000-4000-8000-000000000001",
      kind: "finish_odometer",
      object_path: "test/station/driver/operation/finish-odometer.jpg",
      captured_at: "2026-09-07T20:00:00Z",
    },
  ];

  try {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const screen = await render(
      <QueryClientProvider client={client}>
        <OperationsConsole />
      </QueryClientProvider>,
    );

    await screen.getByRole("button", { name: "Ver fotos" }).click();
    await expect.element(screen.getByRole("heading", { name: "Evidencia privada · TUR-DORI-001" })).toBeInTheDocument();
    await expect.element(screen.getByRole("img", { name: "Odómetro al iniciar" })).toBeInTheDocument();
    await expect.element(screen.getByRole("img", { name: "Odómetro al cerrar" })).toBeInTheDocument();
    expect(signedURLCalls).toEqual([{
      paths: [
        "test/station/driver/operation/start-odometer.jpg",
        "test/station/driver/operation/finish-odometer.jpg",
      ],
      expiresIn: 120,
    }]);
  } finally {
    tableData.shifts = [];
    tableData.shift_evidence = [];
  }
});
