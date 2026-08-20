import { lateText, mxn, rating } from "./format";
import { goalsFor, groupForDate, weekBounds, type Goals } from "./schedule";
import type {
  BonusKind,
  Driver,
  IncomeEntry,
  ShiftRecord,
  ShiftSlot,
  SupervisorReport,
} from "./types";

/** Monthly bonuses: paid at month end, evaluated week by week. The driver must hit
 *  the target on all four weeks of the month to collect. */

export const BONUS_WEEKS_PER_MONTH = 4;

/** Uber quality score is mocked as positive until the API is connected. */
export const MOCK_QUALITY_SCORE = 4.91;

export interface BonusDefinition {
  kind: BonusKind;
  title: string;
  /** Short name used inside notifications: "has perdido el bono de puntualidad". */
  shortName: string;
  monthlyMxn: number;
  /** Quality comes from the Uber API, so the amount is defined by the platform. */
  isExternal: boolean;
  howToWin: string;
  howToLose: string;
}

export const BONUS_DEFINITIONS: BonusDefinition[] = [
  {
    kind: "punctuality",
    title: "Puntualidad y asistencia",
    shortName: "puntualidad",
    monthlyMxn: 1500,
    isExternal: false,
    howToWin: "Inicia turno a tiempo todos los días del mes.",
    howToLose: "Se pierde con una falta o si cierras el mes con tiempo adeudado.",
  },
  {
    kind: "billing",
    title: "Facturación",
    shortName: "facturación",
    monthlyMxn: 1500,
    isExternal: false,
    howToWin: "Llega a la meta semanal de facturación las 4 semanas.",
    howToLose: "Se pierde en la semana que no alcanzas la meta.",
  },
  {
    kind: "care",
    title: "Limpieza y cuidado",
    shortName: "limpieza",
    monthlyMxn: 1000,
    isExternal: false,
    howToWin: "Termina el mes sin reportes de daño ni de limpieza.",
    howToLose: "Se pierde si el supervisor genera un reporte en tu contra.",
  },
  {
    kind: "service",
    title: "Calidad en el servicio",
    shortName: "calidad",
    monthlyMxn: 0,
    isExternal: true,
    howToWin: "Mantén tu calificación de plataforma en verde.",
    howToLose: "Se integra con la API de Uber; en pruebas se muestra positiva.",
  },
];

export const bonusDefinition = (kind: BonusKind): BonusDefinition =>
  BONUS_DEFINITIONS.find((item) => item.kind === kind) ?? BONUS_DEFINITIONS[0];

export const BONUS_TOTAL_MXN = BONUS_DEFINITIONS.reduce((total, item) => total + item.monthlyMxn, 0);

export type BonusWeekStatus = "achieved" | "lost" | "in_progress" | "upcoming";

export const BONUS_STATUS_LABEL: Record<BonusWeekStatus, string> = {
  achieved: "Cumplida",
  lost: "Perdida",
  in_progress: "En curso",
  upcoming: "Por evaluar",
};

export interface BonusWeekRange {
  index: number;
  start: Date;
  end: Date;
}

export interface BonusWeekResult {
  week: BonusWeekRange;
  status: BonusWeekStatus;
  detail: string;
}

export interface BonusEvaluation {
  kind: BonusKind;
  weeks: BonusWeekResult[];
  lostWeeks: number[];
  achievedCount: number;
  isLost: boolean;
  isSecured: boolean;
  /** Money actually payable at month end with the current evaluation. */
  payableMxn: number;
  statusText: string;
}

export interface BonusAlert {
  id: string;
  kind: BonusKind;
  weekIndex: number;
  message: string;
}

export const monthStart = (date: Date): Date => new Date(date.getFullYear(), date.getMonth(), 1);

/** "2026-08", used to key monthly bonus evaluations. */
export const monthKey = (date: Date): string =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;

/** The month is evaluated in four Monday → Sunday windows. */
export const bonusWeeks = (reference: Date): BonusWeekRange[] => {
  const first = weekBounds(monthStart(reference)).start;
  return Array.from({ length: BONUS_WEEKS_PER_MONTH }, (_, offset) => {
    const start = new Date(first);
    start.setDate(start.getDate() + offset * 7);
    const end = new Date(start);
    end.setDate(end.getDate() + 7);
    return { index: offset + 1, start, end };
  });
};

const inWeek = (iso: string, week: BonusWeekRange): boolean => {
  const time = new Date(iso).getTime();
  return time >= week.start.getTime() && time < week.end.getTime();
};

/** Days of the week the driver was scheduled to work and that already finished. */
export const expectedWorkDays = (driver: Driver, week: BonusWeekRange, now: Date): number => {
  let count = 0;
  for (let offset = 0; offset < 7; offset += 1) {
    const day = new Date(week.start);
    day.setDate(day.getDate() + offset);
    if (groupForDate(day) !== driver.shift.group) continue;
    const dayEnd = new Date(day);
    dayEnd.setDate(dayEnd.getDate() + 1);
    if (dayEnd.getTime() > now.getTime()) continue;
    count += 1;
  }
  return count;
};

export interface BonusInput {
  driver: Driver;
  history: ShiftRecord[];
  incomes: IncomeEntry[];
  reports: SupervisorReport[];
  now: Date;
}

const evaluateWeek = (
  kind: BonusKind,
  week: BonusWeekRange,
  input: BonusInput,
  goals: Goals,
): BonusWeekResult => {
  const nowTime = input.now.getTime();
  if (week.start.getTime() > nowTime) {
    return { week, status: "upcoming", detail: "Aún no inicia" };
  }
  const isRunning = nowTime >= week.start.getTime() && nowTime < week.end.getTime();

  if (kind === "punctuality") {
    const records = input.history.filter((record) => inWeek(record.startedAt, week));
    const pending = records.reduce(
      (total, record) => total + Math.max(0, record.lateMinutes - record.paidBackMinutes),
      0,
    );
    const absences = Math.max(0, expectedWorkDays(input.driver, week, input.now) - records.length);

    if (absences > 0) {
      return {
        week,
        status: "lost",
        detail: absences === 1 ? "1 falta registrada" : `${absences} faltas registradas`,
      };
    }
    if (pending > 0) {
      return { week, status: "lost", detail: `Adeudo ${lateText(pending)} sin pagar` };
    }
    const lateTotal = records.reduce((total, record) => total + record.lateMinutes, 0);
    return {
      week,
      status: isRunning ? "in_progress" : "achieved",
      detail: lateTotal > 0 ? `Atraso pagado ${lateText(lateTotal)}` : "Sin atrasos",
    };
  }

  if (kind === "billing") {
    const earned = input.incomes
      .filter((entry) => inWeek(entry.date, week))
      .reduce((total, entry) => total + entry.amountMxn, 0);
    const detail = `${mxn(earned)} de ${mxn(goals.weeklyMxn)}`;
    if (earned >= goals.weeklyMxn) return { week, status: "achieved", detail };
    return { week, status: isRunning ? "in_progress" : "lost", detail };
  }

  if (kind === "care") {
    const reports = input.reports.filter((report) => inWeek(report.createdAt, week));
    if (reports.length > 0) {
      const label = reports[0].kind === "damage" ? "Reporte de daño" : "Reporte de limpieza";
      return { week, status: "lost", detail: label };
    }
    return {
      week,
      status: isRunning ? "in_progress" : "achieved",
      detail: "Sin reportes del supervisor",
    };
  }

  // Mocked positive until the Uber quality API is available.
  return {
    week,
    status: isRunning ? "in_progress" : "achieved",
    detail: `Calificación ${rating(MOCK_QUALITY_SCORE)} · API Uber`,
  };
};

export const evaluateBonuses = (input: BonusInput): BonusEvaluation[] => {
  const goals = goalsFor(input.driver.shift.group);
  const weeks = bonusWeeks(input.now);

  return BONUS_DEFINITIONS.map((definition) => {
    const results = weeks.map((week) => evaluateWeek(definition.kind, week, input, goals));
    const lostWeeks = results.filter((item) => item.status === "lost").map((item) => item.week.index);
    const achievedCount = results.filter((item) => item.status === "achieved").length;
    const isLost = lostWeeks.length > 0;
    const isSecured = achievedCount === results.length && results.length > 0;

    return {
      kind: definition.kind,
      weeks: results,
      lostWeeks,
      achievedCount,
      isLost,
      isSecured,
      payableMxn: isLost ? 0 : definition.monthlyMxn,
      statusText: isLost
        ? `Perdido · semana ${lostWeeks.join(", ")}`
        : isSecured
          ? "Asegurado"
          : `En camino · ${achievedCount} de ${results.length} semanas`,
    };
  });
};

/** First closed week that broke a bonus and has not been announced yet. */
export const pendingBonusAlert = (
  evaluations: BonusEvaluation[],
  notified: string[],
  driverFirstName: string,
  reference: Date,
): BonusAlert | null => {
  for (const evaluation of evaluations) {
    for (const result of evaluation.weeks) {
      if (result.status !== "lost") continue;
      const id = `${evaluation.kind}-${monthKey(reference)}-${result.week.index}`;
      if (notified.includes(id)) continue;
      return {
        id,
        kind: evaluation.kind,
        weekIndex: result.week.index,
        message: `¡${driverFirstName} has perdido el bono de ${bonusDefinition(evaluation.kind).shortName}! Agenda hoy tu lugar en el programa de recuperación de bonos`,
      };
    }
  }
  return null;
};

// MARK: Recovery program

/** A weekday driver recovers on the weekend and the other way around. */
export const recoveryGroup = (driver: Driver) =>
  driver.shift.group === "weekday" ? ("weekend" as const) : ("weekday" as const);

export const recoveryDaysLabel = (driver: Driver): string =>
  driver.shift.group === "weekday" ? "Sábado y domingo" : "Lunes a viernes";

export const isRecoveryDay = (driver: Driver, date: Date): boolean =>
  groupForDate(date) === recoveryGroup(driver);

const startOfDay = (date: Date): Date => {
  const next = new Date(date);
  next.setHours(0, 0, 0, 0);
  return next;
};

/** Bookable when it belongs to the opposite group and has not happened yet. */
export const canBookRecovery = (driver: Driver, date: Date, now: Date): boolean =>
  isRecoveryDay(driver, date) && startOfDay(date).getTime() >= startOfDay(now).getTime();

export const recoverySlotLabel = (slot: ShiftSlot): string =>
  slot === "morning" ? "Matutino" : "Vespertino";
