import { dayShort } from "./format";
import { goalsFor, isSameDay, weekBounds } from "./schedule";
import type { ActiveShift, IncomeEntry, ShiftGroup, ShiftRecord } from "./types";

export interface LateDay {
  date: Date;
  label: string;
  minutes: number;
  paidBackMinutes: number;
  hasShift: boolean;
}

/** Monday → Sunday breakdown of late minutes, the "bitácora" shown in Historial. */
export const weeklyLateBreakdown = (history: ShiftRecord[], now: Date): LateDay[] => {
  const { start } = weekBounds(now);
  const days: LateDay[] = [];

  for (let offset = 0; offset < 7; offset += 1) {
    const date = new Date(start);
    date.setDate(date.getDate() + offset);
    const record = history.find((item) => isSameDay(new Date(item.startedAt), date));
    days.push({
      date,
      label: dayShort(date),
      minutes: record?.lateMinutes ?? 0,
      paidBackMinutes: record?.paidBackMinutes ?? 0,
      hasShift: record !== undefined,
    });
  }

  return days;
};

export const weeklyLateDebt = (history: ShiftRecord[], now: Date): number =>
  weeklyLateBreakdown(history, now).reduce(
    (total, day) => total + Math.max(0, day.minutes - day.paidBackMinutes),
    0,
  );

const inCurrentWeek = (iso: string, now: Date): boolean => {
  const { start, end } = weekBounds(now);
  const time = new Date(iso).getTime();
  return time >= start.getTime() && time < end.getTime();
};

export interface GoalProgress {
  earnedToday: number;
  earnedWeek: number;
  tripsToday: number;
  tripsWeek: number;
  dailyGoal: number;
  weeklyGoal: number;
  hourlyGoal: number;
  tripsGoal: number;
}

export const goalProgress = (
  group: ShiftGroup,
  incomes: IncomeEntry[],
  history: ShiftRecord[],
  activeShift: ActiveShift | null,
  now: Date,
): GoalProgress => {
  const goals = goalsFor(group);

  const todayIncome = incomes
    .filter((entry) => isSameDay(new Date(entry.date), now))
    .reduce((total, entry) => total + entry.amountMxn, 0);
  const todayTrips = incomes
    .filter((entry) => isSameDay(new Date(entry.date), now))
    .reduce((total, entry) => total + entry.trips, 0);

  const weekIncome = incomes
    .filter((entry) => inCurrentWeek(entry.date, now))
    .reduce((total, entry) => total + entry.amountMxn, 0);
  const weekTrips = incomes
    .filter((entry) => inCurrentWeek(entry.date, now))
    .reduce((total, entry) => total + entry.trips, 0);

  const closedTodayFromShifts = history
    .filter((record) => isSameDay(new Date(record.startedAt), now))
    .reduce((total, record) => total + record.earningsMxn, 0);

  return {
    earnedToday: Math.max(todayIncome, closedTodayFromShifts, activeShift?.earningsMxn ?? 0),
    earnedWeek: weekIncome,
    tripsToday: Math.max(todayTrips, activeShift?.trips ?? 0),
    tripsWeek: weekTrips,
    dailyGoal: goals.dailyMxn,
    weeklyGoal: goals.weeklyMxn,
    hourlyGoal: goals.hourlyMxn,
    tripsGoal: goals.tripsPerDay,
  };
};

/** Weekly bars: money earned per calendar day of the current week. */
export const weeklyEarningsByDay = (
  incomes: IncomeEntry[],
  now: Date,
): { label: string; amount: number; isToday: boolean }[] => {
  const { start } = weekBounds(now);
  return Array.from({ length: 7 }, (_, offset) => {
    const date = new Date(start);
    date.setDate(date.getDate() + offset);
    const amount = incomes
      .filter((entry) => isSameDay(new Date(entry.date), date))
      .reduce((total, entry) => total + entry.amountMxn, 0);
    return { label: dayShort(date), amount, isToday: isSameDay(date, now) };
  });
};
