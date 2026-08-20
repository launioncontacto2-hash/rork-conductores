import {
  AlertTriangle,
  BadgeCheck,
  BellRing,
  Camera,
  CircleDollarSign,
  Flag,
  Gauge,
  MapPin,
  QrCode,
  Route,
  Timer,
  TriangleAlert,
  Zap,
} from "lucide-react";
import { useNavigate } from "react-router-dom";

import { DemoClock } from "@/components/DemoClock";
import { BatteryPill, ProgressTrack, StatTile } from "@/components/Pieces";
import { clock, dateLong, firstName, km, lateText, mxn, stopwatch } from "@/lib/format";
import {
  GROUP_LABEL,
  goalsFor,
  isCorrectShiftMoment,
  isPaybackWindow,
  paceTargetMxn,
  paybackWindowLabel,
  SLOT_LABEL,
  SLOT_RANGE_LABEL,
} from "@/lib/schedule";
import { cn } from "@/lib/utils";
import { useFleet } from "@/store/fleet";

const REQUIRED_PHOTOS = 6;

const Turno = () => {
  const {
    driver,
    now,
    activeShift,
    activeVehicle,
    unreadNotices,
    elapsedSeconds,
    estimatedKmDriven,
    weeklyLateDebtMinutes,
  } = useFleet();
  const navigate = useNavigate();

  const goals = goalsFor(driver.shift.group);
  const capturedPhotos = activeShift ? Object.keys(activeShift.photos).length : 0;
  const inspectionPending = activeShift !== null && capturedPhotos < REQUIRED_PHOTOS;
  const canStartNow = isCorrectShiftMoment(driver, now);
  const paybackOpen = isPaybackWindow(driver, now);
  const paceTarget = activeShift ? paceTargetMxn(activeShift.group, elapsedSeconds / 60) : 0;

  return (
    <div className="space-y-5 px-4 pb-4 pt-5">
      {/* Driver identity */}
      <header className="flex items-center gap-3">
        <div className="relative">
          <img
            src={driver.photoUrl}
            alt={driver.name}
            className="size-14 rounded-2xl border border-primary/40 object-cover"
          />
          {activeShift && (
            <span className="absolute -bottom-1 -right-1 grid size-6 place-items-center rounded-full border-2 border-background bg-primary text-primary-foreground">
              <Zap className="size-3.5" strokeWidth={3} />
            </span>
          )}
        </div>
        <div className="min-w-0 flex-1">
          <p className="truncate text-lg font-black leading-tight tracking-tight">{driver.name}</p>
          <p className="flex items-center gap-1 truncate text-xs text-muted-foreground">
            <MapPin className="size-3.5" />
            {driver.station} · {driver.employeeNumber}
          </p>
        </div>
        <div className="flex flex-col items-end gap-1.5">
          <button
            type="button"
            onClick={() => navigate("/avisos")}
            className="press relative grid size-11 place-items-center rounded-2xl border border-border/70 bg-secondary/50"
            aria-label="Notificaciones"
          >
            <BellRing className="size-5" />
            {unreadNotices > 0 && (
              <>
                <span className="absolute right-2 top-2 size-2 rounded-full bg-destructive" />
                <span className="absolute right-2 top-2 size-2 animate-ping-soft rounded-full bg-destructive" />
              </>
            )}
          </button>
          <div className="lg:hidden">
            <DemoClock compact />
          </div>
        </div>
      </header>

      {/* Shift hero */}
      <section className="panel relative overflow-hidden p-5">
        <div className="absolute -right-16 -top-20 size-48 rounded-full bg-primary/10 blur-3xl" />
        <div className="relative">
          <div className="flex items-start justify-between">
            <div>
              <p className="label-caps">{activeShift ? "Turno en curso" : "Próximo turno"}</p>
              <p className="mt-1 text-xl font-black tracking-tight">
                {SLOT_LABEL[driver.shift.slot]} · {GROUP_LABEL[driver.shift.group]}
              </p>
              <p className="text-xs capitalize text-muted-foreground">{dateLong(now)}</p>
            </div>
            <span
              className={cn(
                "rounded-full px-3 py-1 text-[0.68rem] font-bold uppercase tracking-widest",
                activeShift ? "bg-primary/15 text-primary" : canStartNow ? "bg-info/15 text-info" : "bg-secondary text-muted-foreground",
              )}
            >
              {activeShift ? "Activo" : canStartNow ? "Puedes iniciar" : "Fuera de horario"}
            </span>
          </div>

          {activeShift ? (
            <>
              <div className="mt-5 flex items-end justify-between">
                <div>
                  <p className="label-caps">Tiempo transcurrido</p>
                  <p className="tabular text-5xl font-black leading-none tracking-tighter text-primary">
                    {stopwatch(elapsedSeconds)}
                  </p>
                </div>
                <div className="text-right">
                  <p className="label-caps">Inicio</p>
                  <p className="tabular text-2xl font-bold leading-none">{clock(new Date(activeShift.startedAt))}</p>
                  <p className="mt-1 text-[0.7rem] text-muted-foreground">
                    Programado {clock(new Date(activeShift.scheduledStartAt))}
                  </p>
                </div>
              </div>

              <div className="mt-4">
                <ProgressTrack value={elapsedSeconds / 60} goal={9 * 60} />
                <div className="mt-1.5 flex justify-between text-[0.68rem] text-muted-foreground">
                  <span>8 h efectivas + 1 h comida</span>
                  <span>{SLOT_RANGE_LABEL[driver.shift.slot]}</span>
                </div>
              </div>
            </>
          ) : (
            <div className="mt-5 space-y-3">
              <div className="flex items-baseline gap-2">
                <p className="tabular text-4xl font-black tracking-tighter">{SLOT_RANGE_LABEL[driver.shift.slot]}</p>
              </div>
              <p className="text-sm text-muted-foreground">
                Escanea el QR de tu unidad para iniciar. Tolerancia de 10 minutos después de la hora programada.
              </p>
              <button
                type="button"
                onClick={() => navigate("/asignar")}
                className="press flex h-16 w-full items-center justify-center gap-2.5 rounded-2xl bg-primary text-base font-bold text-primary-foreground volt-glow"
              >
                <QrCode className="size-6" strokeWidth={2.4} />
                Escanear vehículo
              </button>
            </div>
          )}
        </div>
      </section>

      {activeShift && activeShift.lateMinutes > 0 && (
        <div className="flex items-start gap-3 rounded-2xl border border-warning/40 bg-warning/10 p-4">
          <TriangleAlert className="mt-0.5 size-5 shrink-0 text-warning" />
          <p className="text-sm leading-snug">
            <span className="font-bold">{firstName(driver.name)}, tienes un atraso de {lateText(activeShift.lateMinutes)} minutos.</span>{" "}
            Recupéralos mañana en tu ventana de {paybackWindowLabel(driver.shift.slot)}.
          </p>
        </div>
      )}

      {inspectionPending && (
        <button
          type="button"
          onClick={() => navigate("/inspeccion")}
          className="press flex w-full items-center gap-3 rounded-2xl border border-info/40 bg-info/10 p-4 text-left"
        >
          <Camera className="size-5 shrink-0 text-info" />
          <span className="flex-1 text-sm leading-snug">
            <span className="font-bold">Registro de inicio incompleto.</span> Faltan{" "}
            {REQUIRED_PHOTOS - capturedPhotos} fotografías del vehículo.
          </span>
        </button>
      )}

      {!activeShift && paybackOpen && weeklyLateDebtMinutes > 0 && (
        <button
          type="button"
          onClick={() => navigate("/historial")}
          className="press flex w-full items-center gap-3 rounded-2xl border border-primary/40 bg-primary/10 p-4 text-left"
        >
          <Timer className="size-5 shrink-0 text-primary" />
          <span className="flex-1 text-sm leading-snug">
            <span className="font-bold">Ventana de pago de atraso abierta</span> ({paybackWindowLabel(driver.shift.slot)}).
            Debes {weeklyLateDebtMinutes} min esta semana.
          </span>
        </button>
      )}

      {/* Vehicle */}
      {activeVehicle ? (
        <section className="panel overflow-hidden">
          <div className="relative h-32">
            <img src={activeVehicle.photoUrl} alt={activeVehicle.model} className="size-full object-cover" />
            <div className="absolute inset-0 bg-gradient-to-t from-card via-card/40 to-transparent" />
            <div className="absolute bottom-3 left-4 right-4 flex items-end justify-between">
              <div>
                <p className="label-caps">Unidad asignada</p>
                <p className="text-2xl font-black leading-none tracking-tight">{activeVehicle.internalNumber}</p>
              </div>
              <BatteryPill level={activeVehicle.batteryPct} />
            </div>
          </div>
          <div className="grid grid-cols-3 divide-x divide-border/60 border-t border-border/60 text-center">
            {[
              { label: "Modelo", value: activeVehicle.model.split(" ").slice(0, 2).join(" ") },
              { label: "Placas", value: activeVehicle.plates },
              { label: "Odómetro", value: km(activeVehicle.odometerKm) },
            ].map((item) => (
              <div key={item.label} className="px-2 py-3">
                <p className="label-caps">{item.label}</p>
                <p className="tabular mt-1 truncate text-sm font-bold">{item.value}</p>
              </div>
            ))}
          </div>
        </section>
      ) : (
        <section className="panel-flat flex items-center gap-3 p-4">
          <Gauge className="size-5 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">Sin vehículo asignado. Tu unidad aparecerá aquí al iniciar turno.</p>
        </section>
      )}

      {/* Live shift metrics */}
      {activeShift && (
        <>
          <div className="grid grid-cols-2 gap-3">
            <StatTile
              label="Km recorridos"
              value={km(estimatedKmDriven)}
              hint="GPS simulado"
              icon={<Route className="size-4 text-muted-foreground" />}
            />
            <StatTile
              label="Ingresos"
              value={mxn(activeShift.earningsMxn)}
              tone={activeShift.earningsMxn >= paceTarget ? "primary" : "warning"}
              hint={`Ritmo objetivo ${mxn(paceTarget)}`}
              icon={<CircleDollarSign className="size-4 text-muted-foreground" />}
            />
            <StatTile
              label="Viajes"
              value={`${activeShift.trips} / ${goals.tripsPerDay}`}
              tone={activeShift.trips >= goals.tripsPerDay ? "primary" : "default"}
              icon={<Flag className="size-4 text-muted-foreground" />}
            />
            <StatTile
              label="Batería inicio"
              value={`${activeShift.startBatteryPct}%`}
              hint={`Odómetro ${km(activeShift.startOdometerKm)}`}
              icon={<Zap className="size-4 text-muted-foreground" />}
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <button
              type="button"
              onClick={() => navigate("/ingreso")}
              className="press flex h-24 flex-col items-center justify-center gap-2 rounded-2xl border border-border/70 bg-secondary/40 text-sm font-bold"
            >
              <CircleDollarSign className="size-6 text-primary" />
              Registrar ingreso
            </button>
            <button
              type="button"
              onClick={() => navigate("/incidencia")}
              className="press flex h-24 flex-col items-center justify-center gap-2 rounded-2xl border border-destructive/40 bg-destructive/10 text-sm font-bold text-destructive"
            >
              <AlertTriangle className="size-6" />
              Reportar incidencia
            </button>
          </div>

          <button
            type="button"
            onClick={() => navigate("/finalizar")}
            className="press flex h-16 w-full items-center justify-center gap-2.5 rounded-2xl border border-primary/50 bg-primary/10 text-base font-bold text-primary"
          >
            <BadgeCheck className="size-6" />
            Finalizar turno
          </button>
        </>
      )}
    </div>
  );
};

export default Turno;
