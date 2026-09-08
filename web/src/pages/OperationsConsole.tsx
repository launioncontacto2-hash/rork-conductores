import { useMutation, useQuery } from "@tanstack/react-query";
import { useState } from "react";
import {
  Activity,
  BatteryCharging,
  Car,
  CircleAlert,
  Clock3,
  Images,
  LogOut,
  Radio,
  RefreshCw,
  ShieldCheck,
  Users,
  Wrench,
} from "lucide-react";

import { useConsoleAuth } from "@/console/ConsoleAuth";
import { TestClockDialog } from "@/console/TestClockDialog";
import { SHARED_TEST_ENVIRONMENT_ID, type TestClockRow } from "@/console/testClock";
import { Badge } from "@/components/ui/badge";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader,
  AlertDialogTitle, AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
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
  profile_id: string;
  employee_number: string;
  status: string;
  shift_group: string | null;
  shift_slot: string | null;
}

interface Device {
  id: string;
  profile_id: string;
  platform: "ios" | "web" | "android";
  app_version: string | null;
  last_seen_at: string;
}

interface Assignment {
  driver_profile_id: string;
  vehicle_id: string;
  kind: string;
  titular_vehicle_id: string | null;
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

interface ClosedShift extends OpenShift {
  finished_at: string;
  end_odometer_km: number;
  end_battery_pct: number;
}

interface ShiftEvidence {
  id: string;
  shift_id: string;
  kind: "start_odometer" | "start_battery" | "finish_odometer";
  object_path: string;
  captured_at: string;
}

interface Incident {
  id: string;
  folio: string;
  vehicle_id: string;
  kind: string;
  severity: string;
  description: string;
  status: string;
  revision: number;
  reported_at: string;
}

interface WorkOrder {
  id: string;
  incident_id: string;
  vehicle_id: string;
  folio: string;
  problem: string;
  priority: string;
  status: string;
  estimated_minutes: number;
  opened_at: string;
  closed_at: string | null;
}

interface Absence {
  id: string;
  driver_profile_id: string;
  folio: string;
  operating_date: string;
  shift_slot: string;
  kind: string;
  reason: string;
  status: string;
  revision: number;
}

interface CoverageVacancy {
  id: string;
  folio: string;
  operating_date: string;
  shift_slot: string;
  reason: string;
  status: string;
  is_critical: boolean;
  revision: number;
}

interface AuditEvent {
  id: string;
  station_id: string;
  actor_profile_id: string | null;
  actor_name: string;
  actor_employee_number: string;
  event_type: string;
  entity_type: string | null;
  entity_id: string | null;
  metadata: Record<string, unknown>;
  occurred_at: string;
}

type PendingCommand =
  | { kind: "review-incident"; id: string; label: string }
  | { kind: "approve-guard"; id: string; label: string }
  | { kind: "approve-absence" | "reject-absence"; id: string; label: string }
  | { kind: "revoke-driver-device"; id: string; label: string };

interface ConsoleSnapshot {
  live: StationLive | null;
  testClock: TestClockRow | null;
  capacity: number | null;
  vehicles: Vehicle[];
  drivers: Driver[];
  assignments: Assignment[];
  shifts: OpenShift[];
  closedShifts: ClosedShift[];
  shiftEvidence: ShiftEvidence[];
  devices: Device[];
  incidents: Incident[];
  workOrders: WorkOrder[];
  absences: Absence[];
  vacancies: CoverageVacancy[];
  auditEvents: AuditEvent[];
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

const deviceIsConnected = (lastSeenAt: string) => Date.now() - new Date(lastSeenAt).getTime() <= 125_000;

const platformLabel: Record<Device["platform"], string> = {
  ios: "iPhone",
  web: "Navegador",
  android: "Android",
};

const auditEventLabel: Record<string, string> = {
  "assignment.created": "Unidad asignada",
  "shift.started": "Turno iniciado",
  "shift.finished": "Turno cerrado",
  "incident.reported": "Incidencia reportada",
  "incident.updated": "Incidencia actualizada",
  "work_order.opened": "Orden de taller abierta",
  "work_order.closed": "Orden de taller cerrada",
  "absence.resolved": "Ausencia resuelta",
  "coverage.guard_approved": "Guardia confirmada",
  "device.revoked": "Acceso de dispositivo retirado",
};

const OperationsConsole = () => {
  const { identity, realtimeConnections, refreshIdentity, signOut } = useConsoleAuth();
  const [assignmentDriverId, setAssignmentDriverId] = useState("");
  const [assignmentVehicleId, setAssignmentVehicleId] = useState("");
  const [assignmentKind, setAssignmentKind] = useState<"titular" | "substitute">("titular");
  const [assignmentReason, setAssignmentReason] = useState("");
  const [pendingCommand, setPendingCommand] = useState<PendingCommand | null>(null);
  const [commandReason, setCommandReason] = useState("");
  const [evidenceShift, setEvidenceShift] = useState<ClosedShift | null>(null);
  const [evidenceURLs, setEvidenceURLs] = useState<Array<ShiftEvidence & { signedURL: string }>>([]);
  const [evidenceError, setEvidenceError] = useState<string | null>(null);
  const [isEvidenceLoading, setIsEvidenceLoading] = useState(false);

  const snapshot = useQuery({
    queryKey: ["console", identity?.station_id, "snapshot"],
    enabled: Boolean(identity),
    refetchInterval: 15_000,
    refetchOnWindowFocus: true,
    queryFn: async (): Promise<ConsoleSnapshot> => {
      if (!supabase || !identity) throw new Error("Supabase o la identidad no están disponibles.");
      const currentIdentity = await refreshIdentity();
      if (!currentIdentity) {
        await signOut();
        throw new Error("La membresía de la consola dejó de estar vigente.");
      }
      // Use the membership just revalidated by the server. React may not have committed
      // the refreshed identity state yet, so reading the captured value here could issue
      // one stale station query before the next 15-second cycle. RLS would still refuse
      // foreign data, but the console should never ask for the obsolete scope at all.
      const stationId = currentIdentity.station_id;
      const [
        live, testClock, capacity, vehicles, drivers, assignments, shifts,
        closedShifts, shiftEvidence, devices, incidents, workOrders, absences, vacancies, auditEvents,
      ] = await Promise.all([
        supabase.from("station_live").select("active_shifts,present_drivers,available_units,units_in_shop,updated_at").eq("station_id", stationId).maybeSingle(),
        supabase.from("test_clock").select("environment_id,anchor_simulated_at,anchor_real_at,speed,is_paused,revision,updated_at").eq("environment_id", currentIdentity.environment_id).maybeSingle(),
        supabase.from("station_capacity_current").select("capacity").eq("station_id", stationId).maybeSingle(),
        supabase.from("vehicles").select("id,internal_number,plate,model,battery_pct,odometer_km,status").eq("station_id", stationId).order("internal_number"),
        supabase.from("console_drivers").select("id,profile_id,employee_number,status,shift_group,shift_slot").eq("station_id", stationId).order("employee_number"),
        supabase.from("assignment_current").select("driver_profile_id,vehicle_id,kind,titular_vehicle_id,assigned_at").eq("station_id", stationId),
        supabase.from("shifts").select("id,folio,driver_profile_id,vehicle_id,started_at,scheduled_end_at").eq("station_id", stationId).eq("status", "open").order("started_at"),
        supabase.from("shifts").select("id,folio,driver_profile_id,vehicle_id,started_at,scheduled_end_at,finished_at,end_odometer_km,end_battery_pct").eq("station_id", stationId).eq("status", "closed").order("finished_at", { ascending: false }).limit(100),
        supabase.from("shift_evidence").select("id,shift_id,kind,object_path,captured_at").eq("station_id", stationId).order("captured_at", { ascending: false }).limit(300),
        supabase.from("devices").select("id,profile_id,platform,app_version,last_seen_at").order("last_seen_at", { ascending: false }),
        supabase.from("incidents").select("id,folio,vehicle_id,kind,severity,description,status,revision,reported_at").eq("station_id", stationId).order("reported_at", { ascending: false }).limit(100),
        supabase.from("work_orders").select("id,incident_id,vehicle_id,folio,problem,priority,status,estimated_minutes,opened_at,closed_at").eq("station_id", stationId).order("opened_at", { ascending: false }).limit(100),
        supabase.from("absences").select("id,driver_profile_id,folio,operating_date,shift_slot,kind,reason,status,revision").eq("station_id", stationId).order("operating_date", { ascending: false }).limit(100),
        supabase.from("coverage_vacancies").select("id,folio,operating_date,shift_slot,reason,status,is_critical,revision").eq("station_id", stationId).order("operating_date", { ascending: false }).limit(100),
        supabase.rpc("console_audit_history", { p_limit: 100 }),
      ]);
      return {
        live: requireData(live) as StationLive | null,
        testClock: requireData(testClock) as TestClockRow | null,
        capacity: (requireData(capacity) as { capacity: number } | null)?.capacity ?? null,
        vehicles: (requireData(vehicles) ?? []) as Vehicle[],
        drivers: (requireData(drivers) ?? []) as Driver[],
        assignments: (requireData(assignments) ?? []) as Assignment[],
        shifts: (requireData(shifts) ?? []) as OpenShift[],
        closedShifts: (requireData(closedShifts) ?? []) as ClosedShift[],
        shiftEvidence: (requireData(shiftEvidence) ?? []) as ShiftEvidence[],
        devices: (requireData(devices) ?? []) as Device[],
        incidents: (requireData(incidents) ?? []) as Incident[],
        workOrders: (requireData(workOrders) ?? []) as WorkOrder[],
        absences: (requireData(absences) ?? []) as Absence[],
        vacancies: (requireData(vacancies) ?? []) as CoverageVacancy[],
        auditEvents: (requireData(auditEvents) ?? []) as AuditEvent[],
      };
    },
  });

  const data = snapshot.data;
  const driverById = new Map(data?.drivers.map((driver) => [driver.id, driver]) ?? []);
  const driverByProfileId = new Map(data?.drivers.map((driver) => [driver.profile_id, driver]) ?? []);
  const vehicleById = new Map(data?.vehicles.map((vehicle) => [vehicle.id, vehicle]) ?? []);
  const connectedDevices = data?.devices.filter((device) => deviceIsConnected(device.last_seen_at)).length ?? 0;
  const availableVehicles = data?.vehicles.filter((vehicle) => vehicle.status === "available") ?? [];
  const selectedCurrentAssignment = data?.assignments.find((assignment) => assignment.driver_profile_id === assignmentDriverId);
  const assignmentReady = Boolean(
    assignmentDriverId && assignmentVehicleId && assignmentReason.trim().length >= 5 &&
      (assignmentKind === "titular" || selectedCurrentAssignment),
  );
  const assignmentMutation = useMutation({
    mutationFn: async () => {
      if (!supabase || !assignmentReady) throw new Error("Completa conductor, unidad y motivo.");
      const { error } = await supabase.rpc("assign_vehicle", {
        p_driver_profile_id: assignmentDriverId,
        p_vehicle_id: assignmentVehicleId,
        p_idempotency_key: `console-${crypto.randomUUID()}`,
        p_kind: assignmentKind,
        p_titular_vehicle_id: assignmentKind === "substitute"
          ? selectedCurrentAssignment?.titular_vehicle_id ?? selectedCurrentAssignment?.vehicle_id
          : null,
        p_note: assignmentReason.trim(),
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: async () => {
      setAssignmentVehicleId("");
      setAssignmentReason("");
      await snapshot.refetch();
    },
  });
  const showShiftEvidence = async (shift: ClosedShift) => {
    if (!supabase) return;
    setEvidenceShift(shift);
    setEvidenceURLs([]);
    setEvidenceError(null);
    setIsEvidenceLoading(true);
    try {
      const rows = data?.shiftEvidence.filter((evidence) => evidence.shift_id === shift.id) ?? [];
      if (!rows.length) throw new Error("Este turno todavía no tiene fotografías registradas.");
      const { data: links, error } = await supabase.storage
        .from("shift-evidence")
        .createSignedUrls(rows.map((evidence) => evidence.object_path), 120);
      if (error) throw new Error(error.message);
      const signedByPath = new Map((links ?? []).map((link) => [link.path, link.signedUrl]));
      const resolved = rows.flatMap((evidence) => {
        const signedURL = signedByPath.get(evidence.object_path);
        return signedURL ? [{ ...evidence, signedURL }] : [];
      });
      if (resolved.length !== rows.length) throw new Error("No fue posible autorizar todas las fotografías.");
      setEvidenceURLs(resolved);
    } catch (error) {
      setEvidenceError(error instanceof Error ? error.message : "No fue posible abrir la evidencia.");
    } finally {
      setIsEvidenceLoading(false);
    }
  };
  const commandMutation = useMutation({
    mutationFn: async ({ command, reason }: { command: PendingCommand; reason: string }) => {
      if (!supabase || reason.trim().length < 5) throw new Error("El motivo debe tener al menos 5 caracteres.");
      const idempotency = `console-${command.kind}-${crypto.randomUUID()}`;
      let response: { error: { message: string } | null };
      if (command.kind === "review-incident") {
        const incident = data?.incidents.find((item) => item.id === command.id);
        if (!incident) throw new Error("La incidencia ya no está disponible.");
        response = await supabase.rpc("update_incident", {
          p_incident_id: incident.id,
          p_expected_revision: incident.revision,
          p_status: "review",
          p_note: reason.trim(),
          p_idempotency_key: idempotency,
        });
      } else if (command.kind === "approve-guard") {
        const vacancy = data?.vacancies.find((item) => item.id === command.id);
        if (!vacancy) throw new Error("La cobertura ya no está disponible.");
        response = await supabase.rpc("approve_guard", {
          p_vacancy_id: vacancy.id,
          p_expected_revision: vacancy.revision,
          p_note: reason.trim(),
          p_idempotency_key: idempotency,
        });
      } else if (command.kind === "approve-absence" || command.kind === "reject-absence") {
        const absence = data?.absences.find((item) => item.id === command.id);
        if (!absence) throw new Error("La ausencia ya no está disponible.");
        response = await supabase.rpc("resolve_absence", {
          p_absence_id: absence.id,
          p_expected_revision: absence.revision,
          p_decision: command.kind === "approve-absence" ? "approved" : "rejected",
          p_note: reason.trim(),
          p_idempotency_key: idempotency,
        });
      } else {
        response = await supabase.rpc("revoke_driver_device", {
          p_device_id: command.id,
          p_note: reason.trim(),
          p_idempotency_key: idempotency,
        });
      }
      if (response.error) throw new Error(response.error.message);
    },
    onSuccess: async () => {
      setPendingCommand(null);
      setCommandReason("");
      await snapshot.refetch();
    },
  });

  if (!identity) return null;

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
                <ShieldCheck className="size-3" /> Operación protegida
              </Badge>
              <Badge variant="outline" className={realtimeConnections === 2 ? "border-emerald-400/40 text-emerald-300" : "border-amber-400/40 text-amber-300"}>
                <Radio className="mr-1 size-3" /> Realtime {realtimeConnections}/2
              </Badge>
            </div>
            <h1 className="mt-3 text-2xl font-black tracking-tight md:text-3xl">Consola DORI</h1>
            <p className="mt-1 text-sm text-muted-foreground">
              {identity.station_name} · {identity.station_code} · {identity.display_name}
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            {identity.environment_id.toLowerCase() === SHARED_TEST_ENVIRONMENT_ID && (
              <TestClockDialog
                clock={data?.testClock}
                stationTimeZone={identity.station_timezone}
                onApplied={() => snapshot.refetch()}
              />
            )}
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

        <nav className="panel flex gap-2 overflow-x-auto p-2" aria-label="Secciones de Consola DORI">
          {[
            ["#operacion", "Operación"],
            ["#asignaciones", "Asignaciones"],
            ["#flota", "Flota"],
            ["#incidencias", "Incidencias y taller"],
            ["#cobertura", "Cobertura"],
            ["#historial", "Historial"],
            ["#auditoria", "Auditoría"],
          ].map(([href, label]) => (
            <a key={href} href={href} className="whitespace-nowrap rounded-lg px-4 py-2 text-sm font-bold text-muted-foreground transition hover:bg-muted hover:text-foreground">
              {label}
            </a>
          ))}
        </nav>

        <section id="operacion" className="scroll-mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {cards.map(({ label, value, icon: Icon, tone }) => (
            <Card key={label} className="panel">
              <CardContent className="flex items-center justify-between p-5">
                <div><p className="label-caps">{label}</p><p className="mt-2 text-3xl font-black tabular">{value}</p></div>
                <Icon className={`size-8 ${tone}`} />
              </CardContent>
            </Card>
          ))}
        </section>

        <Card id="asignaciones" className="panel scroll-mt-4">
          <CardHeader>
            <CardTitle className="text-lg">Asignar unidad</CardTitle>
            <CardDescription>La consola envía el mismo comando transaccional y auditado que el iPhone del supervisor.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4 lg:grid-cols-4">
            <label className="grid gap-2 text-sm font-semibold">
              Conductor
              <select className="h-11 rounded-md border border-border bg-background px-3 font-normal" value={assignmentDriverId} onChange={(event) => setAssignmentDriverId(event.target.value)}>
                <option value="">Seleccionar</option>
                {data?.drivers.map((driver) => <option key={driver.id} value={driver.id}>{driver.employee_number}</option>)}
              </select>
            </label>
            <label className="grid gap-2 text-sm font-semibold">
              Tipo
              <select className="h-11 rounded-md border border-border bg-background px-3 font-normal" value={assignmentKind} onChange={(event) => setAssignmentKind(event.target.value as "titular" | "substitute")}>
                <option value="titular">Titular</option>
                <option value="substitute">Sustituta</option>
              </select>
            </label>
            <label className="grid gap-2 text-sm font-semibold">
              Unidad disponible
              <select className="h-11 rounded-md border border-border bg-background px-3 font-normal" value={assignmentVehicleId} onChange={(event) => setAssignmentVehicleId(event.target.value)}>
                <option value="">Seleccionar</option>
                {availableVehicles.map((vehicle) => <option key={vehicle.id} value={vehicle.id}>{vehicle.internal_number} · {vehicle.plate ?? "sin placa"}</option>)}
              </select>
            </label>
            <label className="grid gap-2 text-sm font-semibold">
              Motivo obligatorio
              <input className="h-11 rounded-md border border-border bg-background px-3 font-normal" value={assignmentReason} onChange={(event) => setAssignmentReason(event.target.value)} placeholder="Mínimo 5 caracteres" />
            </label>
            <div className="lg:col-span-4 flex flex-wrap items-center justify-between gap-3">
              <p className="text-xs text-muted-foreground">
                {assignmentKind === "substitute" && !selectedCurrentAssignment
                  ? "La sustituta requiere una asignación titular vigente."
                  : `${availableVehicles.length} unidades disponibles.`}
              </p>
              <AlertDialog>
                <AlertDialogTrigger asChild>
                  <Button disabled={!assignmentReady || assignmentMutation.isPending}>Confirmar asignación</Button>
                </AlertDialogTrigger>
                <AlertDialogContent>
                  <AlertDialogHeader>
                    <AlertDialogTitle>¿Confirmar cambio operativo?</AlertDialogTitle>
                    <AlertDialogDescription>
                      Se asignará {vehicleById.get(assignmentVehicleId)?.internal_number ?? "la unidad"} a {driverById.get(assignmentDriverId)?.employee_number ?? "el conductor"}. El motivo quedará en auditoría.
                    </AlertDialogDescription>
                  </AlertDialogHeader>
                  <AlertDialogFooter>
                    <AlertDialogCancel>Cancelar</AlertDialogCancel>
                    <AlertDialogAction onClick={() => assignmentMutation.mutate()}>Asignar y registrar</AlertDialogAction>
                  </AlertDialogFooter>
                </AlertDialogContent>
              </AlertDialog>
            </div>
            {assignmentMutation.isError && <p className="lg:col-span-4 text-sm text-destructive">No se pudo asignar: {assignmentMutation.error.message}</p>}
            {assignmentMutation.isSuccess && <p className="lg:col-span-4 text-sm text-emerald-300">La asignación quedó confirmada por Supabase.</p>}
          </CardContent>
        </Card>

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
              <div className="panel-flat flex items-center justify-between p-4"><span className="text-sm text-muted-foreground">Dispositivos conectados</span><strong className="tabular">{connectedDevices}/{data?.devices.length ?? "—"}</strong></div>
              <div className="panel-flat flex items-center justify-between p-4"><span className="text-sm text-muted-foreground">Último evento</span><strong className="text-xs">{data?.live?.updated_at ? formatTime(data.live.updated_at, identity.station_timezone) : "—"}</strong></div>
            </CardContent>
          </Card>
        </section>

        <Card id="flota" className="panel scroll-mt-4">
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

        <Card className="panel">
          <CardHeader>
            <CardTitle className="text-lg">Actividad de dispositivos</CardTitle>
            <CardDescription>El estado conectado exige un heartbeat recibido durante los últimos 125 segundos.</CardDescription>
          </CardHeader>
          <CardContent>
            <Table>
              <TableHeader><TableRow><TableHead>Identidad</TableHead><TableHead>Plataforma</TableHead><TableHead>Versión</TableHead><TableHead>Última actividad</TableHead><TableHead>Conexión</TableHead><TableHead>Acción</TableHead></TableRow></TableHeader>
              <TableBody>
                {data?.devices.map((device) => {
                  const connected = deviceIsConnected(device.last_seen_at);
                  const driver = driverByProfileId.get(device.profile_id);
                  const owner = device.profile_id === identity.profile_id
                    ? identity.employee_number
                    : driver?.employee_number ?? "Personal de estación";
                  return (
                    <TableRow key={device.id}>
                      <TableCell className="font-bold">{owner}</TableCell>
                      <TableCell>{platformLabel[device.platform]}</TableCell>
                      <TableCell>{device.app_version ?? "—"}</TableCell>
                      <TableCell>{formatTime(device.last_seen_at, identity.station_timezone)}</TableCell>
                      <TableCell>
                        <Badge variant="outline" className={connected ? "border-emerald-400/40 text-emerald-300" : "text-muted-foreground"}>
                          {connected ? "Conectado" : "Sin pulso reciente"}
                        </Badge>
                      </TableCell>
                      <TableCell>
                        {driver ? (
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={() => setPendingCommand({
                              kind: "revoke-driver-device",
                              id: device.id,
                              label: `El acceso de ${driver.employee_number} en este ${platformLabel[device.platform]}`,
                            })}
                          >
                            Retirar acceso
                          </Button>
                        ) : "—"}
                      </TableCell>
                    </TableRow>
                  );
                })}
                {!data?.devices.length && <TableRow><TableCell colSpan={6} className="py-8 text-center text-muted-foreground">No hay dispositivos registrados en la estación.</TableCell></TableRow>}
              </TableBody>
            </Table>
          </CardContent>
        </Card>

        <section id="incidencias" className="scroll-mt-4 grid gap-5 xl:grid-cols-2">
          <Card className="panel">
            <CardHeader>
              <CardTitle className="text-lg">Incidencias</CardTitle>
              <CardDescription>Reportes recibidos desde los iPhone de esta estación.</CardDescription>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader><TableRow><TableHead>Folio</TableHead><TableHead>Unidad</TableHead><TableHead>Detalle</TableHead><TableHead>Estado</TableHead></TableRow></TableHeader>
                <TableBody>
                  {data?.incidents.map((incident) => (
                    <TableRow key={incident.id}>
                      <TableCell className="font-bold">{incident.folio}</TableCell>
                      <TableCell>{vehicleById.get(incident.vehicle_id)?.internal_number ?? "—"}</TableCell>
                      <TableCell><p>{incident.description}</p><p className="text-xs text-muted-foreground">{incident.kind} · {incident.severity}</p></TableCell>
                      <TableCell>
                        <div className="flex flex-col items-start gap-2">
                          <Badge variant="outline">{incident.status}</Badge>
                          {incident.status === "open" && (
                            <Button size="sm" variant="outline" onClick={() => setPendingCommand({ kind: "review-incident", id: incident.id, label: incident.folio })}>Recibir</Button>
                          )}
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                  {!data?.incidents.length && <TableRow><TableCell colSpan={4} className="py-8 text-center text-muted-foreground">No hay incidencias registradas.</TableCell></TableRow>}
                </TableBody>
              </Table>
            </CardContent>
          </Card>

          <Card className="panel">
            <CardHeader>
              <CardTitle className="text-lg">Taller</CardTitle>
              <CardDescription>Órdenes y unidades retenidas por mantenimiento.</CardDescription>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader><TableRow><TableHead>Orden</TableHead><TableHead>Unidad</TableHead><TableHead>Prioridad</TableHead><TableHead>Estado</TableHead></TableRow></TableHeader>
                <TableBody>
                  {data?.workOrders.map((order) => (
                    <TableRow key={order.id}>
                      <TableCell><p className="font-bold">{order.folio}</p><p className="text-xs text-muted-foreground">{order.problem}</p></TableCell>
                      <TableCell>{vehicleById.get(order.vehicle_id)?.internal_number ?? "—"}</TableCell>
                      <TableCell>{order.priority} · {order.estimated_minutes} min</TableCell>
                      <TableCell><Badge variant="outline">{order.status}</Badge></TableCell>
                    </TableRow>
                  ))}
                  {!data?.workOrders.length && <TableRow><TableCell colSpan={4} className="py-8 text-center text-muted-foreground">No hay órdenes de taller.</TableCell></TableRow>}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </section>

        <section id="cobertura" className="scroll-mt-4 grid gap-5 xl:grid-cols-2">
          <Card className="panel">
            <CardHeader><CardTitle className="text-lg">Ausencias</CardTitle><CardDescription>Solicitudes que afectan la cobertura de turnos.</CardDescription></CardHeader>
            <CardContent>
              <Table>
                <TableHeader><TableRow><TableHead>Folio</TableHead><TableHead>Conductor</TableHead><TableHead>Fecha</TableHead><TableHead>Estado</TableHead></TableRow></TableHeader>
                <TableBody>
                  {data?.absences.map((absence) => (
                    <TableRow key={absence.id}>
                      <TableCell><p className="font-bold">{absence.folio}</p><p className="text-xs text-muted-foreground">{absence.reason}</p></TableCell>
                      <TableCell>{driverById.get(absence.driver_profile_id)?.employee_number ?? "—"}</TableCell>
                      <TableCell>{absence.operating_date} · {absence.shift_slot}</TableCell>
                      <TableCell>
                        <div className="flex flex-wrap gap-2">
                          <Badge variant="outline">{absence.status}</Badge>
                          {absence.status === "awaiting_authorization" && (
                            <>
                              <Button size="sm" variant="outline" onClick={() => setPendingCommand({ kind: "approve-absence", id: absence.id, label: absence.folio })}>Autorizar</Button>
                              <Button size="sm" variant="ghost" onClick={() => setPendingCommand({ kind: "reject-absence", id: absence.id, label: absence.folio })}>Rechazar</Button>
                            </>
                          )}
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                  {!data?.absences.length && <TableRow><TableCell colSpan={4} className="py-8 text-center text-muted-foreground">No hay solicitudes de ausencia.</TableCell></TableRow>}
                </TableBody>
              </Table>
            </CardContent>
          </Card>

          <Card className="panel">
            <CardHeader><CardTitle className="text-lg">Vacantes de cobertura</CardTitle><CardDescription>Búsquedas de sustitución y su estado oficial.</CardDescription></CardHeader>
            <CardContent>
              <Table>
                <TableHeader><TableRow><TableHead>Folio</TableHead><TableHead>Fecha</TableHead><TableHead>Motivo</TableHead><TableHead>Estado</TableHead></TableRow></TableHeader>
                <TableBody>
                  {data?.vacancies.map((vacancy) => (
                    <TableRow key={vacancy.id}>
                      <TableCell className="font-bold">{vacancy.folio}</TableCell>
                      <TableCell>{vacancy.operating_date} · {vacancy.shift_slot}</TableCell>
                      <TableCell>{vacancy.reason}</TableCell>
                      <TableCell>
                        <div className="flex flex-col items-start gap-2">
                          <Badge variant="outline" className={vacancy.is_critical ? "border-amber-400/40 text-amber-300" : ""}>{vacancy.status}</Badge>
                          {vacancy.status === "reserved" && (
                            <Button size="sm" variant="outline" onClick={() => setPendingCommand({ kind: "approve-guard", id: vacancy.id, label: vacancy.folio })}>Confirmar guardia</Button>
                          )}
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                  {!data?.vacancies.length && <TableRow><TableCell colSpan={4} className="py-8 text-center text-muted-foreground">No hay vacantes de cobertura.</TableCell></TableRow>}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </section>

        <Card id="historial" className="panel scroll-mt-4">
          <CardHeader><CardTitle className="text-lg">Historial de turnos</CardTitle><CardDescription>Últimos 100 cierres confirmados por Supabase.</CardDescription></CardHeader>
          <CardContent>
            <Table>
              <TableHeader><TableRow><TableHead>Folio</TableHead><TableHead>Conductor</TableHead><TableHead>Unidad</TableHead><TableHead>Cierre</TableHead><TableHead>Lecturas finales</TableHead><TableHead>Evidencia</TableHead></TableRow></TableHeader>
              <TableBody>
                {data?.closedShifts.map((shift) => (
                  <TableRow key={shift.id}>
                    <TableCell className="font-bold">{shift.folio}</TableCell>
                    <TableCell>{driverById.get(shift.driver_profile_id)?.employee_number ?? "—"}</TableCell>
                    <TableCell>{vehicleById.get(shift.vehicle_id)?.internal_number ?? "—"}</TableCell>
                    <TableCell>{formatTime(shift.finished_at, identity.station_timezone)}</TableCell>
                    <TableCell>{shift.end_odometer_km.toLocaleString("es-MX")} km · {shift.end_battery_pct}%</TableCell>
                    <TableCell>
                      <Button size="sm" variant="outline" onClick={() => void showShiftEvidence(shift)}>
                        <Images /> Ver fotos
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
                {!data?.closedShifts.length && <TableRow><TableCell colSpan={6} className="py-8 text-center text-muted-foreground">No hay turnos cerrados.</TableCell></TableRow>}
              </TableBody>
            </Table>
          </CardContent>
        </Card>

        <Card id="auditoria" className="panel scroll-mt-4">
          <CardHeader>
            <CardTitle className="text-lg">Auditoría operativa</CardTitle>
            <CardDescription>Últimos 100 eventos inmutables autorizados para esta estación.</CardDescription>
          </CardHeader>
          <CardContent>
            <Table>
              <TableHeader><TableRow><TableHead>Momento</TableHead><TableHead>Acción</TableHead><TableHead>Responsable</TableHead><TableHead>Entidad</TableHead></TableRow></TableHeader>
              <TableBody>
                {data?.auditEvents.map((event) => (
                  <TableRow key={event.id}>
                    <TableCell className="whitespace-nowrap">{formatTime(event.occurred_at, identity.station_timezone)}</TableCell>
                    <TableCell className="font-bold">{auditEventLabel[event.event_type] ?? event.event_type}</TableCell>
                    <TableCell><p>{event.actor_name}</p><p className="text-xs text-muted-foreground">{event.actor_employee_number}</p></TableCell>
                    <TableCell><p>{event.entity_type ?? "Sistema"}</p><p className="max-w-56 truncate font-mono text-[0.65rem] text-muted-foreground">{event.entity_id ?? "—"}</p></TableCell>
                  </TableRow>
                ))}
                {!data?.auditEvents.length && <TableRow><TableCell colSpan={4} className="py-8 text-center text-muted-foreground">No hay eventos auditados visibles.</TableCell></TableRow>}
              </TableBody>
            </Table>
          </CardContent>
        </Card>

        <Dialog open={evidenceShift !== null} onOpenChange={(open) => {
          if (!open) {
            setEvidenceShift(null);
            setEvidenceURLs([]);
            setEvidenceError(null);
          }
        }}>
          <DialogContent className="max-h-[90dvh] max-w-4xl overflow-y-auto">
            <DialogHeader>
              <DialogTitle>Evidencia privada · {evidenceShift?.folio}</DialogTitle>
              <DialogDescription>
                Enlaces temporales por 2 minutos. Las fotografías permanecen en Supabase TEST y no se guardan en este navegador.
              </DialogDescription>
            </DialogHeader>
            {isEvidenceLoading && <p className="py-10 text-center text-sm text-muted-foreground">Autorizando fotografías…</p>}
            {evidenceError && <p className="rounded-lg border border-destructive/40 p-4 text-sm text-destructive">{evidenceError}</p>}
            <div className="grid gap-4 md:grid-cols-3">
              {evidenceURLs.map((evidence) => (
                <figure key={evidence.id} className="panel-flat overflow-hidden p-3">
                  <img
                    src={evidence.signedURL}
                    alt={evidence.kind === "start_battery" ? "Batería al iniciar" : evidence.kind === "start_odometer" ? "Odómetro al iniciar" : "Odómetro al cerrar"}
                    className="aspect-[3/4] w-full rounded-lg bg-black object-contain"
                  />
                  <figcaption className="mt-3 text-xs font-semibold">
                    {evidence.kind === "start_battery" ? "Batería al iniciar" : evidence.kind === "start_odometer" ? "Odómetro al iniciar" : "Odómetro al cerrar"}
                  </figcaption>
                </figure>
              ))}
            </div>
          </DialogContent>
        </Dialog>

        <AlertDialog open={pendingCommand !== null} onOpenChange={(open) => {
          if (!open && !commandMutation.isPending) {
            setPendingCommand(null);
            setCommandReason("");
          }
        }}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Confirmar acción sensible</AlertDialogTitle>
              <AlertDialogDescription>
                {pendingCommand?.label} se modificará mediante un comando transaccional. Escribe el motivo que deberá acompañar la auditoría.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <label className="grid gap-2 text-sm font-semibold">
              Motivo obligatorio
              <textarea className="min-h-24 rounded-md border border-border bg-background p-3 font-normal" value={commandReason} onChange={(event) => setCommandReason(event.target.value)} placeholder="Mínimo 5 caracteres" />
            </label>
            {commandMutation.isError && <p className="text-sm text-destructive">{commandMutation.error.message}</p>}
            <AlertDialogFooter>
              <AlertDialogCancel disabled={commandMutation.isPending}>Cancelar</AlertDialogCancel>
              <AlertDialogAction
                disabled={!pendingCommand || commandReason.trim().length < 5 || commandMutation.isPending}
                onClick={(event) => {
                  event.preventDefault();
                  if (pendingCommand) commandMutation.mutate({ command: pendingCommand, reason: commandReason });
                }}
              >
                {commandMutation.isPending ? "Registrando…" : "Confirmar y auditar"}
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>

        <footer className="flex flex-wrap items-center justify-between gap-2 px-2 pb-3 text-xs text-muted-foreground">
          <span className="inline-flex items-center gap-1.5"><Clock3 className="size-3.5" /> Actualización automática cada 15 segundos</span>
          <span>Los datos operativos no se guardan en este navegador.</span>
        </footer>
      </div>
    </main>
  );
};

export default OperationsConsole;
