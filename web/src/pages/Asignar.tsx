import { BatteryCharging, Gauge, OctagonAlert, PhoneCall, ShieldCheck } from "lucide-react";
import { useCallback, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { toast } from "sonner";

import { BatteryPill, BigButton, ScreenHeader } from "@/components/Pieces";
import { QrScanner } from "@/components/QrScanner";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { clock, km } from "@/lib/format";
import { SLOT_LABEL, SLOT_RANGE_LABEL, validateAssignment } from "@/lib/schedule";
import type { AssignmentIssue, Vehicle } from "@/lib/types";
import { cn } from "@/lib/utils";
import { useFleet } from "@/store/fleet";

const STATUS_LABEL: Record<Vehicle["status"], string> = {
  available: "Disponible",
  occupied: "Ocupado",
  maintenance: "En mantenimiento",
};

const Asignar = () => {
  const { driver, now, vehicles, assignVehicle, pushNotice } = useFleet();
  const navigate = useNavigate();

  const [vehicle, setVehicle] = useState<Vehicle | null>(null);
  const [odometer, setOdometer] = useState<string>("");
  const [battery, setBattery] = useState<string>("");
  const [issues, setIssues] = useState<AssignmentIssue[]>([]);

  const knownCodes = useMemo(() => vehicles.map((item) => item.qrCode), [vehicles]);

  const handleDetected = useCallback(
    (code: string): void => {
      const normalized = code.trim().toUpperCase();
      const found = vehicles.find(
        (item) => item.qrCode.toUpperCase() === normalized || item.internalNumber.toUpperCase() === normalized,
      );
      if (!found) {
        toast.error("Unidad no encontrada", { description: `El código ${normalized} no pertenece a la flotilla.` });
        return;
      }
      setVehicle(found);
      setBattery(String(found.batteryPct));
      toast.success(`Unidad ${found.internalNumber} leída`, { description: found.model });
    },
    [vehicles],
  );

  const confirm = (): void => {
    if (!vehicle) return;
    const odometerValue = Number(odometer);
    const batteryValue = Number(battery);

    if (!Number.isFinite(odometerValue) || odometerValue <= 0) {
      toast.error("Captura el kilometraje de inicio");
      return;
    }
    if (!Number.isFinite(batteryValue) || batteryValue <= 0 || batteryValue > 100) {
      toast.error("Captura el nivel de batería de inicio");
      return;
    }

    const found = validateAssignment({
      driver,
      vehicle,
      now,
      odometerKm: odometerValue,
      batteryPct: batteryValue,
    });

    if (found.length > 0) {
      setIssues(found);
      return;
    }

    const shift = assignVehicle({ vehicle, odometerKm: odometerValue, batteryPct: batteryValue });
    if (shift.lateMinutes > 0) {
      pushNotice({
        kind: "reminder",
        title: "Inicio de turno con atraso",
        body: `Iniciaste ${shift.lateMinutes} minutos después de la hora programada. Se registró en tu bitácora.`,
      });
    }
    toast.success(`Unidad ${vehicle.internalNumber} asignada`, { description: "Continúa con el registro fotográfico." });
    navigate("/inspeccion", { replace: true });
  };

  return (
    <div className="pb-6">
      <ScreenHeader
        title="Asignación de vehículo"
        subtitle={`${SLOT_LABEL[driver.shift.slot]} · ${SLOT_RANGE_LABEL[driver.shift.slot]}`}
        onBack={() => navigate("/turno")}
      />

      <div className="space-y-5 px-4 pt-5">
        {!vehicle ? (
          <>
            <QrScanner onDetected={handleDetected} knownCodes={knownCodes} />
            <p className="text-center text-xs text-muted-foreground">
              Hora del dispositivo {clock(now)} · la lectura valida turno, autorización, batería y kilometraje.
            </p>
          </>
        ) : (
          <>
            <section className="panel overflow-hidden">
              <div className="relative h-36">
                <img src={vehicle.photoUrl} alt={vehicle.model} className="size-full object-cover" />
                <div className="absolute inset-0 bg-gradient-to-t from-card via-card/30 to-transparent" />
                <div className="absolute bottom-3 left-4 right-4 flex items-end justify-between">
                  <div>
                    <p className="label-caps">Número interno</p>
                    <p className="text-3xl font-black leading-none tracking-tight">{vehicle.internalNumber}</p>
                  </div>
                  <BatteryPill level={vehicle.batteryPct} />
                </div>
              </div>
              <dl className="divide-y divide-border/60">
                {[
                  { label: "Modelo", value: vehicle.model },
                  { label: "Placas", value: vehicle.plates },
                  { label: "Kilometraje registrado", value: km(vehicle.odometerKm) },
                  { label: "Nivel de batería", value: `${vehicle.batteryPct}%` },
                  { label: "Estación asignada", value: vehicle.station },
                  { label: "Estado", value: STATUS_LABEL[vehicle.status] },
                ].map((row) => (
                  <div key={row.label} className="flex items-center justify-between gap-4 px-4 py-3">
                    <dt className="label-caps">{row.label}</dt>
                    <dd
                      className={cn(
                        "tabular truncate text-sm font-bold",
                        row.label === "Estado" && vehicle.status !== "available" && "text-destructive",
                      )}
                    >
                      {row.value}
                    </dd>
                  </div>
                ))}
              </dl>
            </section>

            <section className="space-y-3">
              <div>
                <label className="label-caps mb-1.5 flex items-center gap-1.5" htmlFor="odometer">
                  <Gauge className="size-3.5" /> Kilometraje de inicio
                </label>
                <Input
                  id="odometer"
                  value={odometer}
                  onChange={(event) => setOdometer(event.target.value.replace(/[^\d]/g, ""))}
                  inputMode="numeric"
                  placeholder={String(vehicle.odometerKm)}
                  className="tabular h-16 rounded-2xl text-center text-2xl font-black"
                />
                <div className="mt-2 flex gap-2">
                  <button
                    type="button"
                    onClick={() => setOdometer(String(vehicle.odometerKm))}
                    className="press rounded-full border border-border/70 bg-secondary/40 px-3 py-1.5 text-xs font-semibold"
                  >
                    Usar registrado {km(vehicle.odometerKm)}
                  </button>
                </div>
              </div>

              <div>
                <label className="label-caps mb-1.5 flex items-center gap-1.5" htmlFor="battery">
                  <BatteryCharging className="size-3.5" /> Nivel de batería de inicio
                </label>
                <Input
                  id="battery"
                  value={battery}
                  onChange={(event) => setBattery(event.target.value.replace(/[^\d]/g, "").slice(0, 3))}
                  inputMode="numeric"
                  placeholder="96"
                  className="tabular h-16 rounded-2xl text-center text-2xl font-black"
                />
              </div>
            </section>

            <div className="space-y-3">
              <BigButton onClick={confirm} icon={<ShieldCheck className="size-5" />}>
                Confirmar asignación
              </BigButton>
              <BigButton tone="outline" onClick={() => setVehicle(null)}>
                Escanear otra unidad
              </BigButton>
            </div>
          </>
        )}
      </div>

      <Dialog open={issues.length > 0} onOpenChange={(open) => !open && setIssues([])}>
        <DialogContent className="max-w-sm rounded-3xl border-destructive/40">
          <DialogHeader>
            <div className="mx-auto grid size-14 place-items-center rounded-2xl bg-destructive/15 text-destructive">
              <OctagonAlert className="size-8" />
            </div>
            <DialogTitle className="text-center">Asignación bloqueada</DialogTitle>
            <DialogDescription className="text-center">
              No puedes iniciar turno con esta unidad hasta resolver lo siguiente.
            </DialogDescription>
          </DialogHeader>
          <ul className="space-y-2">
            {issues.map((issue) => (
              <li
                key={issue.code}
                className="rounded-2xl border border-destructive/40 bg-destructive/10 p-3 text-sm font-semibold leading-snug"
              >
                {issue.message}
              </li>
            ))}
          </ul>
          <div className="space-y-2">
            <BigButton
              tone="danger"
              icon={<PhoneCall className="size-5" />}
              onClick={() => {
                setIssues([]);
                toast.success("Supervisor notificado", {
                  description: "Se envió el reporte a la estación con el detalle de la unidad.",
                });
              }}
            >
              Notificar a supervisor
            </BigButton>
            <BigButton tone="outline" onClick={() => setIssues([])}>
              Corregir datos
            </BigButton>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default Asignar;
