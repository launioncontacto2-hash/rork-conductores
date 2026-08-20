import { CalendarRange, Flag, Timer, TrendingUp } from "lucide-react";
import { useNavigate } from "react-router-dom";

import { ProgressTrack, RingGauge, StatTile } from "@/components/Pieces";
import { mxn } from "@/lib/format";
import { GROUP_LABEL, goalsFor, paceTargetMxn, paybackWindowLabel, SLOT_LABEL } from "@/lib/schedule";
import { goalProgress, weeklyEarningsByDay } from "@/lib/selectors";
import { cn } from "@/lib/utils";
import { useFleet } from "@/store/fleet";

const Metas = () => {
  const { driver, now, incomes, history, activeShift, elapsedSeconds, weeklyLateDebtMinutes } = useFleet();
  const navigate = useNavigate();

  const goals = goalsFor(driver.shift.group);
  const progress = goalProgress(driver.shift.group, incomes, history, activeShift, now);
  const week = weeklyEarningsByDay(incomes, now);
  const maxBar = Math.max(goals.dailyMxn, ...week.map((day) => day.amount));
  const paceTarget = activeShift ? paceTargetMxn(activeShift.group, elapsedSeconds / 60) : 0;
  const paceDelta = progress.earnedToday - paceTarget;
  const missingToday = Math.max(0, goals.dailyMxn - progress.earnedToday);
  const missingTrips = Math.max(0, goals.tripsPerDay - progress.tripsToday);

  return (
    <div className="space-y-5 px-4 pb-4 pt-6">
      <header>
        <p className="label-caps">Metas semanales</p>
        <h1 className="text-2xl font-black tracking-tight">
          {GROUP_LABEL[driver.shift.group]} · {SLOT_LABEL[driver.shift.slot]}
        </h1>
      </header>

      <section className="panel flex flex-col items-center p-5">
        <RingGauge
          value={progress.earnedToday}
          goal={goals.dailyMxn}
          headline={mxn(progress.earnedToday)}
          caption={`de ${mxn(goals.dailyMxn)} hoy`}
        />
        <p
          className={cn(
            "mt-2 flex items-center gap-1.5 text-sm font-bold",
            missingToday === 0 ? "text-primary" : "text-warning",
          )}
        >
          <TrendingUp className="size-4" />
          {missingToday === 0 ? "Meta del día cumplida" : `Faltan ${mxn(missingToday)} para la meta del día`}
        </p>

        {activeShift && (
          <div className="mt-4 w-full rounded-2xl border border-border/60 bg-secondary/30 p-3">
            <div className="flex items-center justify-between text-xs">
              <span className="label-caps">Ritmo por hora</span>
              <span className={cn("tabular font-bold", paceDelta >= 0 ? "text-primary" : "text-warning")}>
                {paceDelta >= 0 ? "+" : "−"}
                {mxn(Math.abs(paceDelta))} vs objetivo
              </span>
            </div>
            <div className="mt-2">
              <ProgressTrack value={progress.earnedToday} goal={goals.dailyMxn} marker={paceTarget} />
            </div>
            <p className="mt-1.5 text-[0.68rem] text-muted-foreground">
              Objetivo acumulado {mxn(paceTarget)} · {mxn(goals.hourlyMxn)} por hora
            </p>
          </div>
        )}
      </section>

      <div className="grid grid-cols-3 gap-3">
        <StatTile label="Por hora" value={mxn(goals.hourlyMxn)} />
        <StatTile label="Por día" value={mxn(goals.dailyMxn)} />
        <StatTile label="Semana" value={mxn(goals.weeklyMxn)} />
      </div>

      <section className="panel p-5">
        <div className="flex items-center justify-between">
          <p className="label-caps flex items-center gap-1.5">
            <CalendarRange className="size-3.5" /> Avance semanal
          </p>
          <p className="tabular text-sm font-bold">
            {mxn(progress.earnedWeek)} <span className="text-muted-foreground">/ {mxn(goals.weeklyMxn)}</span>
          </p>
        </div>
        <div className="mt-3">
          <ProgressTrack value={progress.earnedWeek} goal={goals.weeklyMxn} />
        </div>

        <div className="mt-5 flex h-32 items-end gap-2">
          {week.map((day) => {
            const height = maxBar > 0 ? Math.max(4, (day.amount / maxBar) * 100) : 4;
            const reached = day.amount >= goals.dailyMxn;
            return (
              <div key={day.label} className="flex flex-1 flex-col items-center gap-1.5">
                <div className="relative flex h-full w-full items-end">
                  <span
                    className={cn(
                      "w-full rounded-t-md transition-[height] duration-700",
                      reached ? "bg-primary" : day.amount > 0 ? "bg-primary/40" : "bg-secondary",
                      day.isToday && "ring-1 ring-primary/70",
                    )}
                    style={{ height: `${height}%` }}
                  />
                </div>
                <span className={cn("text-[0.62rem] font-semibold", day.isToday ? "text-primary" : "text-muted-foreground")}>
                  {day.label}
                </span>
              </div>
            );
          })}
        </div>
      </section>

      <section className="panel p-5">
        <div className="flex items-center justify-between">
          <p className="label-caps flex items-center gap-1.5">
            <Flag className="size-3.5" /> Viajes de hoy
          </p>
          <p className="tabular text-sm font-bold">
            {progress.tripsToday} <span className="text-muted-foreground">/ {goals.tripsPerDay}</span>
          </p>
        </div>
        <div className="mt-3 grid grid-cols-7 gap-1.5">
          {Array.from({ length: goals.tripsPerDay }, (_, index) => (
            <span
              key={index}
              className={cn(
                "h-7 rounded-md",
                index < progress.tripsToday ? "bg-primary" : "bg-secondary",
              )}
            />
          ))}
        </div>
        <p className="mt-3 text-xs text-muted-foreground">
          {missingTrips === 0
            ? "Meta de viajes cumplida. ¡Excelente ritmo!"
            : `Faltan ${missingTrips} viajes para la meta. Recupéralos hoy o mañana.`}
        </p>
      </section>

      <button
        type="button"
        onClick={() => navigate("/historial")}
        className={cn(
          "press flex w-full items-center gap-3 rounded-2xl border p-4 text-left",
          weeklyLateDebtMinutes > 0 ? "border-warning/40 bg-warning/10" : "border-border/70 bg-secondary/40",
        )}
      >
        <Timer className={cn("size-5 shrink-0", weeklyLateDebtMinutes > 0 ? "text-warning" : "text-primary")} />
        <span className="flex-1 text-sm leading-snug">
          <span className="font-bold">
            {weeklyLateDebtMinutes > 0
              ? `Debes ${weeklyLateDebtMinutes} minutos esta semana`
              : "Sin atrasos esta semana"}
          </span>
          <br />
          <span className="text-muted-foreground">
            Ventana de pago {paybackWindowLabel(driver.shift.slot)} · ver bitácora
          </span>
        </span>
      </button>
    </div>
  );
};

export default Metas;
