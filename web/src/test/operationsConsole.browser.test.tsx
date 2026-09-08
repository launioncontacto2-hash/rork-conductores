import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { vi } from "vitest";
import { render } from "vitest-browser-react";

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
  devices: [],
  incidents: [],
  work_orders: [],
  absences: [],
  coverage_vacancies: [],
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
    rpc: async () => ({ data: null, error: null }),
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
});
