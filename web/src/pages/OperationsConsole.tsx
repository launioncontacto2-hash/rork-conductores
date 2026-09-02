import { useQuery } from "@tanstack/react-query";
import {
  Activity,
  BatteryCharging,
  Car,
  CircleAlert,
  Clock3,
  LogOut,
  Radio,
  RefreshCw,
  ShieldCheck,
  Users,
  Wrench,
} from "lucide-react";

import { useConsoleAuth } from "@/console/ConsoleAuth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { supabase } from "@/lib/supabase";

interface StationLive {
  active_shifts: number;
  present_drivers: number;
  available_units: number;
  units_in_shop: number;
  updated_at: string;
}

interface Vehicle {
  id: string;
  internal_number: string;
  plate: string | null;
  model: string;
  battery_pct: number | null;
  odometer_km: number;
  status: "available" | "occupied" | "maintenance";
}

interface Driver {
  id: string;
  employee_number: string;
  status: string;
}

interface Assignment {
  driver_profile_id: string;
  vehicle_id: string;
  kind: string;
  assigned_at: string;
}

interface OpenShift {
  id: string;
  folio: string;
  driver_profile_id: string;
  vehicle_id: string;
  started_at: string;
  scheduled_end_at: string;
}

interface ConsoleSnapshot {
  live: StationLive | null;
  capacity: number | null;
  vehicles: Vehicle[];
  drivers: Driver[];
  assignments: Assignment[];
  shifts: OpenShift[];
  activeDevices: number;
}

const requireData = <T,>(result: { data: T | null; error: { message: string } | null }): T => {
  if (result.error) throw new Error(result.error.message);
  return result.data as T;
};

const formatTime = (value: string, timeZone: string) =>
  new Intl.DateTimeFormat("es-MX", { dateStyle: "short", timeStyle: "short", timeZone }).format(new Date(value));

const statusLabel: Record<Vehicle["status"], string> = {
  available: "Disponible",
  occupied: "Asignada",
  maintenance: "Taller",
};

const OperationsConsole = () => {
  const { identity, realtimeConnections, signOut } = useConsoleAuth();

  const snapshot = useQuery({
    queryKey: ["console", identity?.station_id, "snapshot"],
    enabled: Boolean(identity),
    refetchInterval: 15_000,
    refetchOnWindowFocus: true,
    queryFn: async (): Promise<ConsoleSnapshot> => {
      if (!supabase || !identity) throw new Error("Supabase o la identidad no están disponibles.");
      const stationId = identity.station_id;
      const [live, capacity, vehicles, drivers, assignments, shifts, devices] = await Promise.all([
        supabase.from("station_live").select("active_shifts,present_drivers,available_units,units_in_shop,updated_at").eq("station_id", stationId).maybeSingle(),
        supabase.from("station_capacity_current").select("capacity").eq("station_id", stationId).maybeSingle(),
        supabase.from("vehicles").select("id,internal_number,plate,model,battery_pct,odometer_km,status").eq("station_id", stationId).order("internal_number"),
        supabase.from("driver_profiles").select("id,employee_number,status").eq("station_id", stationId).order("employee_number"),
        supabase.from("assignment_current").select("driver_profile_id,vehicle_id,kind,assigned_at").eq("station_id", stationId),
        supabase.from("shifts").select("id,folio,driver_profile_id,vehicle_id,started_at,scheduled_end_at").eq("station_id", stationId).eq("status", "open").order("started_at"),
        supabase.from("devices").select("id", { count: "exact", head: true }),
      ]);
      return {
        live: requireData(live) as StationLive | null,
        capacity: (requireData(capacity) as { capacity: number } | null)?.capacity ?? null,
        vehicles: (requireData(vehicles) ?? []) as Vehicle[],
        drivers: (requireData(drivers) ?? []) as Driver[],
        assignments: (requireData(assignments) ?? []) as Assignment[],
        shifts: (requireData(shifts) ?? []) as OpenShift[],
        activeDevices: devices.error ? 0 : devices.count ?? 0,
      };
    },
  });

  if (!identity) return null;

  const data = snapshot.data;
  const driverById = new Map(data?.drivers.map((driver) => [driver.id, driver]) ?? []);
  const vehicleById = new Map(data?.vehicles.map((vehicle) => [vehicle.id, vehicle]) ?? []);
  const cards = [
    { label: "Turnos activos", value: data?.live?.active_shifts ?? "—", icon: Activity, tone: "text-primary" },
    { label: "Conductores presentes", value: data?.live?.present_drivers ?? "—", icon: Users, tone: "text-cyan-300" },
    { label: "Unidades disponibles", value: data?.live?.available_units ?? "—", icon: Car, tone: "text-emerald-300" },
    { label: "Unidades en taller", value: data?.live?.units_in_shop ?? "—", icon: Wrench, tone: "text-amber-300" },
  ];

  return (
    <main className="station-bg min-h-dvh px-4 py-5 md:px-8 md:py-7">
      <div className="mx-auto max-w-7xl space-y-5">
        <header className="panel flex flex-col gap-4 p-5 md:flex-row md:items-center md:justify-between">
          <div>
            <div className="flex flex-wrap items-center gap-2">
              <Badge className="bg-amber-400 text-black hover:bg-amber-400">TEST</Badge>
              <Badge variant="outline" className="gap-1.5 border-primary/35 text-primary">
                <ShieldCheck className="size-3" /> Solo lectura
              </Badge>
              <Badge variant="outline" className={realtimeConnections === 2 ? "border-emerald-400/40 text-emerald-300" : "border-amber-400/40 text-amber-300"}>
                <Radio className="mr-1 size-3" /> Realtime {realtimeConnections}/2
              </Badge>
            </div>
            <h1 className="mt-3 text-2xl font-black tracking-tight md:text-3xl">Consola de operación</h1>
            <p className="mt-1 text-sm text-muted-foreground">
              {identity.station_name} · {identity.station_code} · {identity.display_name}
            </p>
          </div>
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => snapshot.refetch()} disabled={snapshot.isFetching}>
              <RefreshCw className={snapshot.isFetching ? "animate-spin" : ""} /> Actualizar
            </Button>
            <Button variant="ghost" onClick={() => void signOut()}><LogOut /> Salir</Button>
          </div>
        </header>

        {snapshot.isError && (
          <div className="panel flex items-center gap-3 border-destructive/50 p-4 text-destructive">
            <CircleAlert /> No se pudo leer la estación: {snapshot.error.message}
          </div>
        )}

        <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {cards.map(({ label, value, icon: Icon, tone }) => (
            <Card key={label} className="panel">
              <CardContent className="flex items-center justify-between p-5">
                <div><p className="label-caps">{label}</p><p className="mt-2 text-3xl font-black tabular">{value}</p></div>
                <Icon className={`size-8 ${tone}`} />
              </CardContent>
            </Card>
          ))}
        </section>

        <section className="grid gap-5 xl:grid-cols-[1.15fr_0.85fr]">
          <Card className="panel">
            <CardHeader>
              <CardTitle className="text-lg">Turnos abiertos</CardTitle>
              <CardDescription>Un turno iniciado en iPhone aparece aquí en la siguiente actualización.</CardDescription>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader><TableRow><TableHead>Folio</TableHead><TableHead>Conductor</TableHead><TableHead>Unidad</TableHead><TableHead>Inicio</TableHead></TableRow></TableHeader>
                <TableBody>
                  {data?.shifts.map((shift) => (
                    <TableRow key={shift.id}>
                      <TableCell className="font-bold">{shift.folio}</TableCell>
                      <TableCell>{driverById.get(shift.driver_profile_id)?.employee_number ?? "—"}</TableCell>
                      <TableCell>{vehicleById.get(shift.vehicle_id)?.internal_number ?? "—"}</TableCell>
                      <TableCell>{formatTime(shift.started_at, identity.station_timezone)}</TableCell>
                    </TableRow>
                  ))}
                  {!data?.shifts.length && <TableRow><TableCell colSpan={4} className="py-8 text-center text-muted-foreground">No hay turnos abiertos.</TableCell></TableRow>}
                </TableBody>
              </Table>
            </CardContent>
          </Card>

          <Card className="panel">
            <CardHeader><CardTitle className="text-lg">Estado de estación</CardTitle><CardDescription>Capacidad y conectividad observada.</CardDescription></CardHeader>
            <CardContent className="grid gap-3 sm:grid-cols-3 xl:grid-cols-1">
              <div className="panel-flat flex items-center justify-between p-4"><span className="text-sm text-muted-foreground">Capacidad autorizada</span><strong className="tabular">{data?.capacity ?? "—"}</strong></div>
              <div className="panel-flat flex items-center justify-between p-4"><span className="text-sm text-muted-foreground">Navegadores/dispositivos</span><strong className="tabular">{data?.activeDevices ?? "—"}</strong></div>
              <div className="panel-flat flex items-center justify-between p-4"><span className="text-sm text-muted-foreground">Último evento</span><strong className="text-xs">{data?.live?.updated_at ? formatTime(data.live.updated_at, identity.station_timezone) : "—"}</strong></div>
            </CardContent>
          </Card>
        </section>

        <Card className="panel">
          <CardHeader><CardTitle className="text-lg">Flotilla</CardTitle><CardDescription>{data?.vehicles.length ?? 0} unidades visibles dentro de la membresía de estación.</CardDescription></CardHeader>
          <CardContent>
            <Table>
              <TableHeader><TableRow><TableHead>Unidad</TableHead><TableHead>Modelo</TableHead><TableHead>Estado</TableHead><TableHead>Batería</TableHead><TableHead>Odómetro</TableHead><TableHead>Conductor</TableHead></TableRow></TableHeader>
              <TableBody>
                {data?.vehicles.map((vehicle) => {
                  const assignment = data.assignments.find((item) => item.vehicle_id === vehicle.id);
                  return (
                    <TableRow key={vehicle.id}>
                      <TableCell><p className="font-bold">{vehicle.internal_number}</p><p className="text-xs text-muted-foreground">{vehicle.plate ?? "Sin placa"}</p></TableCell>
                      <TableCell>{vehicle.model}</TableCell>
                      <TableCell><Badge variant="outline">{statusLabel[vehicle.status]}</Badge></TableCell>
                      <TableCell><span className="inline-flex items-center gap-1.5 tabular"><BatteryCharging className="size-4 text-primary" />{vehicle.battery_pct ?? "—"}%</span></TableCell>
                      <TableCell className="tabular">{vehicle.odometer_km.toLocaleString("es-MX")} km</TableCell>
                      <TableCell>{assignment ? driverById.get(assignment.driver_profile_id)?.employee_number ?? "—" : "Sin asignar"}</TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </CardContent>
        </Card>

        <footer className="flex flex-wrap items-center justify-between gap-2 px-2 pb-3 text-xs text-muted-foreground">
          <span className="inline-flex items-center gap-1.5"><Clock3 className="size-3.5" /> Actualización automática cada 15 segundos</span>
          <span>Los datos operativos no se guardan en este navegador.</span>
        </footer>
      </div>
    </main>
  );
};

export default OperationsConsole;
