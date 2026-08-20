import {
  AlertTriangle,
  BadgeCheck,
  Banknote,
  CalendarClock,
  CalendarPlus,
  Check,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  CircleDashed,
  Info,
  Minus,
  Sparkles,
  Star,
  UserRoundCheck,
  X,
} from "lucide-react";
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { toast } from "sonner";

import { BigButton, ProgressTrack, StatTile } from "@/components/Pieces";
import {
  BONUS_STATUS_LABEL,
  BONUS_TOTAL_MXN,
  MOCK_QUALITY_SCORE,
  bonusDefinition,
  canBookRecovery,
  monthStart,
  recoveryDaysLabel,
  recoveryGroup,
  type BonusAlert,
  type BonusEvaluation,
  type BonusWeekResult,
  type BonusWeekStatus,
} from "@/lib/bonuses";
import { dateShort, dayNumber, firstName, monthLong, mxn, rating } from "@/lib/format";
import { GROUP_LABEL, SLOT_LABEL, SLOT_RANGE_LABEL } from "@/lib/schedule";
import type { BonusKind, ShiftSlot } from "@/lib/types";
import { cn } from "@/lib/utils";
import { useFleet } from "@/store/fleet";

const STATUS_STYLE: Record<BonusWeekStatus, { dot: string; ring: string; text: string; icon: ReactNode }> = {
  achieved: {
    dot: "bg-primary",
    ring: "border-primary/50 bg-primary/15 text-primary",
    text: "text-primary",
    icon: <Check className="size-3.5" strokeWidth={3.2} />,
  },
  lost: {
    dot: "bg-destructive",
    ring: "border-destructive/50 bg-destructive/15 text-destructive",
    text: "text-destructive",
    icon: <X className="size-3.5" strokeWidth={3.2} />,
  },
  in_progress: {
    dot: "bg-info",
    ring: "border-info/50 bg-info/15 text-info",
    text: "text-info",
    icon: <CircleDashed className="size-3.5" strokeWidth={2.6} />,
  },
  upcoming: {
    dot: "bg-border",
    ring: "border-border bg-secondary/40 text-muted-foreground",
    text: "text-muted-foreground",
    icon: <Minus className="size-3.5" strokeWidth={3} />,
  },
};

const BONUS_ICON: Record<BonusKind, ReactNode> = {
  punctuality: <CalendarClock className="size-5" />,
  billing: <Banknote className="size-5" />,
  care: <Sparkles className="size-5" />,
  service: <Star className="size-5" />,
};

const WeekChip = ({ result }: { result: BonusWeekResult }) => {
  const style = STATUS_STYLE[result.status];
  return (
    <div className="flex flex-1 flex-col items-center gap-1.5">
      <span className={cn("grid size-9 place-items-center rounded-full border", style.ring)}>{style.icon}</span>
      <span className="text-[0.6rem] font-bold text-muted-foreground">S{result.week.index}</span>
    </div>
  );
};

const BonusCard = ({ evaluation }: { evaluation: BonusEvaluation }) => {
  const [isOpen, setIsOpen] = useState<boolean>(false);
  const definition = bonusDefinition(evaluation.kind);

  return (
    <article className="panel p-5">
      <header className="flex items-start gap-3">
        <span
          className={cn(
            "grid size-11 shrink-0 place-items-center rounded-2xl",
            evaluation.isLost ? "bg-destructive/12 text-destructive" : "bg-primary/12 text-primary",
          )}
        >
          {BONUS_ICON[evaluation.kind]}
        </span>
        <div className="min-w-0 flex-1">
          <h3 className="text-sm font-black leading-tight">{definition.title}</h3>
          <p className={cn("text-[0.7rem]", evaluation.isLost ? "text-destructive" : "text-muted-foreground")}>
            {evaluation.statusText}
          </p>
        </div>
        <div className="text-right">
          <p
            className={cn(
              "tabular text-sm font-black",
              evaluation.isLost ? "text-muted-foreground line-through decoration-destructive" : "text-primary",
            )}
          >
            {definition.isExternal ? "Uber" : mxn(definition.monthlyMxn)}
          </p>
          <p className="label-caps">Mensual</p>
        </div>
      </header>

      <div className="mt-4 flex gap-2">
        {evaluation.weeks.map((result) => (
          <WeekChip key={result.week.index} result={result} />
        ))}
      </div>

      <ul className="mt-4 space-y-1.5">
        {evaluation.weeks
          .filter((result) => result.status !== "upcoming")
          .map((result) => (
            <li key={result.week.index} className="flex items-center gap-2 text-[0.7rem]">
              <span className={cn("w-5 font-black", STATUS_STYLE[result.status].text)}>S{result.week.index}</span>
              <span className="text-muted-foreground">{result.detail}</span>
              <span className="ml-auto text-[0.65rem] text-muted-foreground/70">
                {dayNumber(result.week.start)} — {dayNumber(new Date(result.week.end.getTime() - 86400000))}
              </span>
            </li>
          ))}
      </ul>

      <button
        type="button"
        onClick={() => setIsOpen((prev) => !prev)}
        className="press mt-4 flex w-full items-center gap-1.5 text-[0.7rem] font-bold text-info"
      >
        {isOpen ? <ChevronUp className="size-3.5" /> : <Info className="size-3.5" />}
        {isOpen ? "Ocultar reglas" : "Cómo se gana y cómo se pierde"}
      </button>

      {isOpen && (
        <div className="panel-flat mt-3 space-y-2 p-3 text-[0.7rem] text-muted-foreground">
          <p className="flex gap-2">
            <BadgeCheck className="size-3.5 shrink-0 text-primary" />
            {definition.howToWin}
          </p>
          <p className="flex gap-2">
            <X className="size-3.5 shrink-0 text-destructive" />
            {definition.howToLose}
          </p>
          {evaluation.kind === "service" && (
            <p className="flex gap-2">
              <Star className="size-3.5 shrink-0 text-info" />
              En pruebas la métrica es positiva: {rating(MOCK_QUALITY_SCORE)} estrellas.
            </p>
          )}
        </div>
      )}
    </article>
  );
};

/** Bonus recovery program: reserve days on the opposite group and pick the slot. */
const RecoveryProgram = ({ suggestedBonus }: { suggestedBonus: BonusKind }) => {
  const { driver, now, recoveryBookings, bookRecovery, cancelRecovery } = useFleet();
  const [anchor, setAnchor] = useState<Date>(() => monthStart(now));
  const [selected, setSelected] = useState<Date | null>(null);
  const [slot, setSlot] = useState<ShiftSlot>(driver.shift.slot);
  const [bonus, setBonus] = useState<BonusKind>(suggestedBonus);

  const cells = useMemo<(Date | null)[]>(() => {
    const days = new Date(anchor.getFullYear(), anchor.getMonth() + 1, 0).getDate();
    const leading = (anchor.getDay() + 6) % 7;
    const result: (Date | null)[] = Array.from({ length: leading }, () => null);
    for (let day = 1; day <= days; day += 1) {
      result.push(new Date(anchor.getFullYear(), anchor.getMonth(), day));
    }
    return result;
  }, [anchor]);

  const bookedDays = useMemo(
    () => new Set(recoveryBookings.map((item) => new Date(item.date).toDateString())),
    [recoveryBookings],
  );

  const shiftMonth = (value: number): void => {
    setAnchor((prev) => new Date(prev.getFullYear(), prev.getMonth() + value, 1));
    setSelected(null);
  };

  const reserve = (): void => {
    if (!selected) return;
    const saved = bookRecovery({ date: selected, slot, bonus });
    if (saved) {
      toast.success("Reserva confirmada", {
        description: `${dateShort(selected)} · turno ${SLOT_LABEL[slot].toLowerCase()} ${SLOT_RANGE_LABEL[slot]}`,
      });
      setSelected(null);
    } else {
      toast.error("Ese día ya no está disponible", { description: "Elige otro día del calendario." });
    }
  };

  return (
    <section id="recuperacion" className="panel p-5">
      <header className="flex items-start gap-3">
        <span className="grid size-11 shrink-0 place-items-center rounded-2xl bg-primary/12 text-primary">
          <CalendarPlus className="size-5" />
        </span>
        <div>
          <h3 className="text-sm font-black leading-tight">Programa de recuperación de bonos</h3>
          <p className="text-[0.7rem] text-muted-foreground">
            Turnos disponibles: {recoveryDaysLabel(driver)}
          </p>
        </div>
      </header>

      <p className="mt-3 text-[0.7rem] leading-relaxed text-muted-foreground">
        Tu grupo es {GROUP_LABEL[driver.shift.group].toLowerCase()}, así que recuperas en{" "}
        {GROUP_LABEL[recoveryGroup(driver)].toLowerCase()}. Elige el día y el turno en el que quieres laborar.
      </p>

      <p className="label-caps mt-5">Turno a laborar</p>
      <div className="mt-2 grid grid-cols-2 gap-2">
        {(["morning", "evening"] as ShiftSlot[]).map((option) => (
          <button
            key={option}
            type="button"
            onClick={() => setSlot(option)}
            className={cn(
              "press rounded-2xl border p-3 text-left",
              slot === option ? "border-primary/60 bg-primary/12" : "border-border bg-secondary/40",
            )}
          >
            <p className="text-sm font-bold">{SLOT_LABEL[option]}</p>
            <p className="tabular text-[0.65rem] text-muted-foreground">{SLOT_RANGE_LABEL[option]}</p>
          </button>
        ))}
      </div>

      <p className="label-caps mt-5">Bono a recuperar</p>
      <div className="mt-2 flex flex-wrap gap-2">
        {(["punctuality", "billing", "care"] as BonusKind[]).map((option) => (
          <button
            key={option}
            type="button"
            onClick={() => setBonus(option)}
            className={cn(
              "press rounded-full px-3 py-2 text-[0.7rem] font-bold",
              bonus === option
                ? "bg-primary text-primary-foreground"
                : "border border-border bg-secondary/40 text-muted-foreground",
            )}
          >
            {bonusDefinition(option).title}
          </button>
        ))}
      </div>

      <div className="mt-5 flex items-center justify-between">
        <button
          type="button"
          onClick={() => shiftMonth(-1)}
          className="press grid size-9 place-items-center rounded-full bg-secondary/60"
          aria-label="Mes anterior"
        >
          <ChevronLeft className="size-4" />
        </button>
        <p className="text-sm font-black">{monthLong(anchor)}</p>
        <button
          type="button"
          onClick={() => shiftMonth(1)}
          className="press grid size-9 place-items-center rounded-full bg-secondary/60"
          aria-label="Mes siguiente"
        >
          <ChevronRight className="size-4" />
        </button>
      </div>

      <div className="mt-3 grid grid-cols-7 gap-1 text-center">
        {["L", "M", "M", "J", "V", "S", "D"].map((label, index) => (
          <span key={`${label}-${index}`} className="text-[0.6rem] font-black text-muted-foreground">
            {label}
          </span>
        ))}
      </div>

      <div className="mt-1 grid grid-cols-7 gap-1">
        {cells.map((day, index) => {
          if (!day) return <span key={`empty-${index}`} className="h-11" />;
          const isBooked = bookedDays.has(day.toDateString());
          const isAvailable = canBookRecovery(driver, day, now) && !isBooked;
          const isSelected = selected?.toDateString() === day.toDateString();
          const isToday = day.toDateString() === now.toDateString();

          return (
            <button
              key={day.toISOString()}
              type="button"
              disabled={!isAvailable}
              onClick={() => setSelected(day)}
              className={cn(
                "press flex h-11 flex-col items-center justify-center gap-0.5 rounded-xl text-xs font-bold disabled:pointer-events-none",
                isSelected && "bg-primary text-primary-foreground",
                !isSelected && isBooked && "bg-primary/15 text-primary",
                !isSelected && !isBooked && isAvailable && "bg-secondary/70",
                !isSelected && !isBooked && !isAvailable && "bg-secondary/20 text-muted-foreground/40",
                isToday && "ring-1 ring-info/70",
              )}
            >
              <span className="tabular">{day.getDate()}</span>
              {isBooked ? (
                <Check className="size-2.5" strokeWidth={4} />
              ) : isAvailable && !isSelected ? (
                <span className="size-1 rounded-full bg-primary" />
              ) : null}
            </button>
          );
        })}
      </div>

      <div className="mt-4 space-y-3">
        {selected ? (
          <p className="panel-flat px-3 py-2.5 text-[0.7rem] font-semibold">
            {dateShort(selected)} · {SLOT_LABEL[slot]} {SLOT_RANGE_LABEL[slot]}
          </p>
        ) : (
          <p className="text-[0.7rem] text-muted-foreground">
            Selecciona un día disponible (marcado con punto) para reservar tu lugar.
          </p>
        )}
        <BigButton onClick={reserve} disabled={!selected} icon={<Check className="size-5" />}>
          Reservar día de recuperación
        </BigButton>
      </div>

      {recoveryBookings.length > 0 && (
        <div className="mt-5 space-y-2">
          <p className="label-caps">Mis reservas</p>
          {[...recoveryBookings]
            .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())
            .map((booking) => (
              <div key={booking.id} className="panel-flat flex items-center gap-3 p-3">
                <div className="min-w-0 flex-1">
                  <p className="text-xs font-bold">{dateShort(new Date(booking.date))}</p>
                  <p className="text-[0.65rem] text-muted-foreground">
                    {SLOT_LABEL[booking.slot]} {SLOT_RANGE_LABEL[booking.slot]} · bono de{" "}
                    {bonusDefinition(booking.bonus).shortName}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => cancelRecovery(booking.id)}
                  className="press rounded-full bg-destructive/12 px-3 py-1.5 text-[0.65rem] font-bold text-destructive"
                >
                  Cancelar
                </button>
              </div>
            ))}
        </div>
      )}
    </section>
  );
};

const Bonos = () => {
  const { driver, now, bonusEvaluations, bonusPayableMxn, supervisorReports, raiseBonusAlert } = useFleet();
  const [alert, setAlert] = useState<BonusAlert | null>(null);
  const raisedRef = useRef<boolean>(false);

  useEffect(() => {
    if (raisedRef.current) return;
    raisedRef.current = true;
    setAlert(raiseBonusAlert());
  }, [raiseBonusAlert]);

  const lost = bonusEvaluations.filter((item) => item.isLost);
  const secured = bonusEvaluations.filter((item) => item.isSecured).length;

  const scrollToCalendar = (): void => {
    document.getElementById("recuperacion")?.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  return (
    <div className="space-y-4 px-4 pt-4">
      <header className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-black leading-tight">Bonos</h1>
          <p className="text-xs text-muted-foreground">{monthLong(now)}</p>
        </div>
        <span className="label-caps">
          {GROUP_LABEL[driver.shift.group]} · {SLOT_LABEL[driver.shift.slot]}
        </span>
      </header>

      <section className="panel p-5">
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="label-caps">Bono mensual estimado</p>
            <p
              className={cn(
                "tabular mt-1 text-4xl font-black leading-none tracking-tighter",
                bonusPayableMxn === BONUS_TOTAL_MXN ? "text-primary" : "text-warning",
              )}
            >
              {mxn(bonusPayableMxn)}
            </p>
            <p className="mt-1 text-xs text-muted-foreground">
              de {mxn(BONUS_TOTAL_MXN)} posibles + calidad de servicio
            </p>
          </div>
          <div className="panel-flat px-4 py-3 text-center">
            <p className="tabular text-lg font-black">
              {secured}/{bonusEvaluations.length}
            </p>
            <p className="label-caps">Asegurados</p>
          </div>
        </div>

        <div className="mt-4">
          <ProgressTrack value={bonusPayableMxn} goal={BONUS_TOTAL_MXN} />
        </div>

        <p className="mt-3 flex items-start gap-2 text-[0.7rem] text-muted-foreground">
          <CalendarClock className="size-3.5 shrink-0 text-primary" />
          Se pagan a fin de mes y se evalúan cada semana: debes cumplir las 4 semanas.
        </p>
      </section>

      {lost.length > 0 && (
        <section className="rounded-2xl border border-destructive/40 bg-destructive/10 p-4">
          <p className="flex items-start gap-2 text-sm font-bold">
            <AlertTriangle className="size-4 shrink-0 text-destructive" />
            {lost.length === 1
              ? `¡${firstName(driver.name)} has perdido el bono de ${bonusDefinition(lost[0].kind).shortName}!`
              : `Tienes ${lost.length} bonos en riesgo este mes`}
          </p>
          <p className="mt-1 pl-6 text-xs text-muted-foreground">
            Agenda hoy tu lugar en el programa de recuperación de bonos.
          </p>
          <button
            type="button"
            onClick={scrollToCalendar}
            className="press mt-3 flex h-12 w-full items-center justify-center gap-2 rounded-2xl border border-border bg-secondary/50 text-sm font-bold"
          >
            <CalendarPlus className="size-4" />
            Agendar recuperación
          </button>
        </section>
      )}

      <div className="flex flex-wrap gap-x-4 gap-y-2 px-1">
        {(["achieved", "lost", "in_progress", "upcoming"] as BonusWeekStatus[]).map((status) => (
          <span key={status} className="flex items-center gap-1.5 text-[0.62rem] font-semibold text-muted-foreground">
            <span className={cn("size-2 rounded-full", STATUS_STYLE[status].dot)} />
            {BONUS_STATUS_LABEL[status]}
          </span>
        ))}
      </div>

      {bonusEvaluations.map((evaluation) => (
        <BonusCard key={evaluation.kind} evaluation={evaluation} />
      ))}

      <RecoveryProgram suggestedBonus={lost[0]?.kind ?? "punctuality"} />

      {supervisorReports.length > 0 && (
        <section className="panel space-y-3 p-5">
          <p className="flex items-center gap-2 text-xs font-semibold text-muted-foreground">
            <UserRoundCheck className="size-4" />
            Reportes del supervisor
          </p>
          {supervisorReports.map((report) => (
            <div key={report.id} className="panel-flat p-3">
              <div className="flex items-center justify-between">
                <p className="text-xs font-bold text-destructive">
                  {report.kind === "damage" ? "Reporte de daño" : "Reporte de limpieza"}
                </p>
                <p className="text-[0.65rem] text-muted-foreground">{dateShort(new Date(report.createdAt))}</p>
              </div>
              <p className="mt-1 text-[0.7rem] text-muted-foreground">{report.note}</p>
              <p className="mt-1 text-[0.65rem] font-bold text-muted-foreground/80">
                {report.vehicleInternalNumber}
              </p>
            </div>
          ))}
        </section>
      )}

      <div className="grid grid-cols-2 gap-3">
        <StatTile
          label="Calidad Uber"
          value={rating(MOCK_QUALITY_SCORE)}
          hint="Métrica simulada, pendiente de API"
          tone="primary"
          icon={<Star className="size-4 text-muted-foreground" />}
        />
        <StatTile
          label="Semanas evaluadas"
          value={`${bonusEvaluations[0]?.weeks.filter((week) => week.status !== "upcoming").length ?? 0} / 4`}
          hint="Corte semanal automático"
          icon={<ChevronDown className="size-4 text-muted-foreground" />}
        />
      </div>

      {alert && (
        <div className="fixed inset-0 z-50 grid place-items-end bg-background/70 p-4 backdrop-blur-sm">
          <div className="panel w-full space-y-4 p-6 text-center">
            <span className="mx-auto grid size-14 place-items-center rounded-2xl bg-destructive/15 text-destructive">
              <AlertTriangle className="size-7" />
            </span>
            <h2 className="text-base font-black leading-snug">{alert.message}</h2>
            <p className="text-xs text-muted-foreground">
              Corte de la semana {alert.weekIndex}. El bono de {bonusDefinition(alert.kind).shortName} se recupera
              reservando un día en tu turno opuesto.
            </p>
            <BigButton
              icon={<CalendarPlus className="size-5" />}
              onClick={() => {
                setAlert(null);
                window.setTimeout(scrollToCalendar, 120);
              }}
            >
              Ir al programa
            </BigButton>
          </div>
        </div>
      )}
    </div>
  );
};

export default Bonos;
