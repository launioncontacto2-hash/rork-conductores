import {
  AlertTriangle,
  CarFront,
  CircleDollarSign,
  Image as ImageIcon,
  Timer,
  TimerReset,
} from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";

import { ProgressTrack, StatTile } from "@/components/Pieces";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { clock, dateShort, durationText, km, lateText, mxn } from "@/lib/format";
import { isPaybackWindow, paybackWindowLabel, SLOT_LABEL } from "@/lib/schedule";
import { weeklyLateBreakdown } from "@/lib/selectors";
import type { IncidentKind, IncidentStatus } from "@/lib/types";
import { cn } from "@/lib/utils";
import { useFleet } from "@/store/fleet";

const INCIDENT_LABEL: Record<IncidentKind, string> = {
  accident: "Accidente",
  damage: "Daño",
  mechanical: "Falla mecánica",
};

const INCIDENT_STATUS: Record<IncidentStatus, { label: string; className: string }> = {
  open: { label: "Abierta", className: "bg-destructive/15 text-destructive" },
  review: { label: "En revisión", className: "bg-warning/15 text-warning" },
  closed: { label: "Cerrada", className: "bg-primary/15 text-primary" },
};

const Historial = () => {
  const { driver, now, history, incomes, incidents, weeklyLateDebtMinutes, payLateTime } = useFleet();
  const [tab, setTab] = useState<string>("turnos");

  const lateDays = weeklyLateBreakdown(history, now);
  const paybackOpen = isPaybackWindow(driver, now);

  const pay = (): void => {
    const applied = payLateTime(30);
    if (applied === 0) {
      toast.info("No tienes atrasos pendientes esta semana");
      return;
    }
    toast.success(`${applied} minutos abonados`, {
      description: "Tiempo registrado dentro de la ventana autorizada.",
    });
  };

  return (
    <div className="space-y-5 px-4 pb-4 pt-6">
      <header>
        <p className="label-caps">Bitácora del conductor</p>
        <h1 className="text-2xl font-black tracking-tight">Historial</h1>
      </header>

      {/* Weekly late log */}
      <section className="panel p-5">
        <div className="flex items-start justify-between">
          <div>
            <p className="label-caps flex items-center gap-1.5">
              <Timer className="size-3.5" /> Atrasos de la semana
            </p>
            <p className={cn("tabular mt-1 text-3xl font-black tracking-tight", weeklyLateDebtMinutes > 0 ? "text-warning" : "text-primary")}>
              {weeklyLateDebtMinutes} min
            </p>
          </div>
          <span className="rounded-full bg-secondary px-3 py-1 text-[0.68rem] font-bold uppercase tracking-widest text-muted-foreground">
            {SLOT_LABEL[driver.shift.slot]}
          </span>
        </div>

        <div className="mt-4 grid grid-cols-7 gap-1.5">
          {lateDays.map((day) => {
            const pending = Math.max(0, day.minutes - day.paidBackMinutes);
            return (
              <div key={day.date.toISOString()} className="text-center">
                <div
                  className={cn(
                    "grid h-14 place-items-center rounded-xl border text-sm font-black",
                    !day.hasShift
                      ? "border-border/50 bg-secondary/20 text-muted-foreground/50"
                      : pending > 0
                        ? "border-warning/50 bg-warning/15 text-warning"
                        : "border-primary/40 bg-primary/10 text-primary",
                  )}
                >
                  <span className="tabular">{day.hasShift ? pending : "—"}</span>
                </div>
                <p className="mt-1 text-[0.62rem] font-semibold text-muted-foreground">{day.label}</p>
              </div>
            );
          })}
        </div>

        <p className="mt-3 text-xs text-muted-foreground">
          Minutos pendientes por día. Ventana de pago {paybackWindowLabel(driver.shift.slot)} · las horas fuera de esa
          ventana no se descuentan.
        </p>

        <button
          type="button"
          onClick={pay}
          disabled={!paybackOpen || weeklyLateDebtMinutes === 0}
          className="press mt-4 flex h-14 w-full items-center justify-center gap-2 rounded-2xl bg-primary text-sm font-bold text-primary-foreground disabled:pointer-events-none disabled:opacity-40"
        >
          <TimerReset className="size-5" />
          {paybackOpen ? "Abonar 30 min de atraso" : `Disponible ${paybackWindowLabel(driver.shift.slot)}`}
        </button>
      </section>

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList className="grid h-12 w-full grid-cols-3 rounded-2xl bg-secondary/50 p-1">
          {[
            { id: "turnos", label: "Turnos" },
            { id: "ingresos", label: "Ingresos" },
            { id: "incidencias", label: "Incidencias" },
          ].map((item) => (
            <TabsTrigger
              key={item.id}
              value={item.id}
              className="rounded-xl text-xs font-bold data-[state=active]:bg-primary data-[state=active]:text-primary-foreground"
            >
              {item.label}
            </TabsTrigger>
          ))}
        </TabsList>

        <TabsContent value="turnos" className="mt-4 space-y-3">
          {history.slice(0, 12).map((record) => {
            const started = new Date(record.startedAt);
            const ended = new Date(record.endedAt);
            const pending = Math.max(0, record.lateMinutes - record.paidBackMinutes);
            return (
              <article key={record.id} className="panel-flat p-4">
                <div className="flex items-start justify-between">
                  <div>
                    <p className="text-sm font-bold capitalize">{dateShort(started)}</p>
                    <p className="tabular text-xs text-muted-foreground">
                      {clock(started)} — {clock(ended)} · {record.vehicleInternalNumber}
                    </p>
                  </div>
                  <span
                    className={cn(
                      "rounded-full px-2.5 py-1 text-[0.65rem] font-bold uppercase tracking-wider",
                      pending > 0 ? "bg-warning/15 text-warning" : "bg-primary/15 text-primary",
                    )}
                  >
                    {pending > 0 ? `Atraso ${lateText(pending)}` : "A tiempo"}
                  </span>
                </div>
                <div className="mt-3 grid grid-cols-4 gap-2 text-center">
                  {[
                    { label: "Km", value: km(record.endOdometerKm - record.startOdometerKm) },
                    { label: "Duración", value: durationText((ended.getTime() - started.getTime()) / 60000) },
                    { label: "Viajes", value: String(record.trips) },
                    { label: "Ingresos", value: mxn(record.earningsMxn) },
                  ].map((cell) => (
                    <div key={cell.label} className="rounded-xl bg-background/60 py-2">
                      <p className="label-caps">{cell.label}</p>
                      <p className="tabular mt-0.5 text-xs font-bold">{cell.value}</p>
                    </div>
                  ))}
                </div>
              </article>
            );
          })}
        </TabsContent>

        <TabsContent value="ingresos" className="mt-4 space-y-3">
          {incomes.slice(0, 15).map((entry) => (
            <article key={entry.id} className="panel-flat flex items-center gap-3 p-4">
              <span className="grid size-11 shrink-0 place-items-center rounded-xl bg-primary/12 text-primary">
                <CircleDollarSign className="size-5" />
              </span>
              <div className="min-w-0 flex-1">
                <p className="text-sm font-bold capitalize">{dateShort(new Date(entry.date))}</p>
                <p className="text-xs text-muted-foreground">
                  {entry.platform} · {entry.trips} viajes
                  {entry.note ? ` · ${entry.note}` : ""}
                </p>
              </div>
              {entry.evidence && (
                <img src={entry.evidence} alt="Evidencia" className="size-10 rounded-lg object-cover" />
              )}
              <p className="tabular text-base font-black">{mxn(entry.amountMxn)}</p>
            </article>
          ))}
        </TabsContent>

        <TabsContent value="incidencias" className="mt-4 space-y-3">
          {incidents.length === 0 && (
            <p className="panel-flat p-6 text-center text-sm text-muted-foreground">Sin incidencias registradas.</p>
          )}
          {incidents.map((incident) => {
            const status = INCIDENT_STATUS[incident.status];
            return (
              <article key={incident.id} className="panel-flat p-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-center gap-2">
                    <AlertTriangle className="size-4 text-destructive" />
                    <p className="text-sm font-bold">{INCIDENT_LABEL[incident.kind]}</p>
                  </div>
                  <span className={cn("rounded-full px-2.5 py-1 text-[0.65rem] font-bold uppercase", status.className)}>
                    {status.label}
                  </span>
                </div>
                <p className="mt-2 text-xs leading-relaxed text-muted-foreground">{incident.description}</p>
                <div className="mt-3 flex items-center gap-3 text-[0.68rem] text-muted-foreground">
                  <span className="flex items-center gap-1">
                    <CarFront className="size-3.5" /> {incident.vehicleInternalNumber}
                  </span>
                  <span className="capitalize">{dateShort(new Date(incident.createdAt))}</span>
                  {incident.photos.length > 0 && (
                    <span className="flex items-center gap-1">
                      <ImageIcon className="size-3.5" /> {incident.photos.length}
                    </span>
                  )}
                </div>
                {incident.photos.length > 0 && (
                  <div className="mt-3 flex gap-2">
                    {incident.photos.map((photo, index) => (
                      <img key={index} src={photo} alt="Evidencia" className="size-16 rounded-xl object-cover" />
                    ))}
                  </div>
                )}
              </article>
            );
          })}
        </TabsContent>

      </Tabs>
    </div>
  );
};

export default Historial;
