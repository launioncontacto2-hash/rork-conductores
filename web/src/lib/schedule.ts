import type {
  AssignmentIssue,
  Driver,
  ShiftGroup,
  ShiftSlot,
  Vehicle,
} from "./types";

/** A correct start is accepted up to 10 minutes after the scheduled time. */
export const GRACE_MINUTES = 10;
/** Daily trip target for every shift. */
export const TRIPS_GOAL_PER_DAY = 14;
/** Minimum battery required to take a unit out. */
export const MIN_BATTERY_PCT = 70;
/** The unit may be scanned this early before the scheduled start. */
export const EARLY_ASSIGNMENT_MINUTES = 30;

export interface DayWindow {
  startMinutes: number;
  endMinutes: number;
}

/** 8 worked hours + 1 hour meal break per slot. */
export const SHIFT_WINDOWS: Record<ShiftSlot, DayWindow> = {
  morning: { startMinutes: 5 * 60, endMinutes: 14 * 60 },
  evening: { startMinutes: 14 * 60 + 30, endMinutes: 23 * 60 + 30 },
};

export const SLOT_LABEL: Record<ShiftSlot, string> = {
  morning: "Matutino",
  evening: "Vespertino",
};

export const GROUP_LABEL: Record<ShiftGroup, string> = {
  weekday: "Entre semana",
  weekend: "Fin de semana",
};

export const SLOT_RANGE_LABEL: Record<ShiftSlot, string> = {
  morning: "05:00 — 14:00",
  evening: "14:30 — 23:30",
};

export interface Goals {
  hourlyMxn: number;
  dailyMxn: number;
  weeklyMxn: number;
  tripsPerDay: number;
}

const GOALS: Record<ShiftGroup, Goals> = {
  weekday: { hourlyMxn: 190, dailyMxn: 1520, weeklyMxn: 7600, tripsPerDay: TRIPS_GOAL_PER_DAY },
  weekend: { hourlyMxn: 250, dailyMxn: 2000, weeklyMxn: 4000, tripsPerDay: TRIPS_GOAL_PER_DAY },
};

export const goalsFor = (group: ShiftGroup): Goals => GOALS[group];

export const groupForDate = (date: Date): ShiftGroup => {
  const day = date.getDay();
  return day === 0 || day === 6 ? "weekend" : "weekday";
};

export const minutesOfDay = (date: Date): number => date.getHours() * 60 + date.getMinutes();

export const atMinutes = (date: Date, minutes: number): Date => {
  const next = new Date(date);
  next.setHours(0, Math.round(minutes), 0, 0);
  return next;
};

/** Scheduled start for the driver's slot on the given day. */
export const scheduledStart = (slot: ShiftSlot, day: Date): Date =>
  atMinutes(day, SHIFT_WINDOWS[slot].startMinutes);

export const scheduledEnd = (slot: ShiftSlot, day: Date): Date =>
  atMinutes(day, SHIFT_WINDOWS[slot].endMinutes);

/** Late time is 0 inside the 10 minute grace period, otherwise the full delay. */
export const lateMinutesFor = (scheduled: Date, actual: Date): number => {
  const diff = Math.floor((actual.getTime() - scheduled.getTime()) / 60000);
  return diff > GRACE_MINUTES ? diff : 0;
};

/** The calendar day matches the driver's group and the clock is inside the slot. */
export const isCorrectShiftMoment = (driver: Driver, now: Date): boolean => {
  if (groupForDate(now) !== driver.shift.group) return false;
  const current = minutesOfDay(now);
  const window = SHIFT_WINDOWS[driver.shift.slot];
  return current >= window.startMinutes - EARLY_ASSIGNMENT_MINUTES && current <= window.endMinutes;
};

/**
 * Late time payback window: the morning shift pays back the hour before its start
 * (04:00), the evening shift the hour after it ends (23:30 — 00:30).
 */
export const isPaybackWindow = (driver: Driver, now: Date): boolean => {
  const current = minutesOfDay(now);
  if (driver.shift.slot === "morning") {
    return current >= 4 * 60 && current < 5 * 60;
  }
  return current >= 23 * 60 + 30 || current < 30;
};

export const paybackWindowLabel = (slot: ShiftSlot): string =>
  slot === "morning" ? "04:00 — 05:00" : "23:30 — 00:30";

/** Monday 00:00 → Sunday 23:59 of the week containing `now`. */
export const weekBounds = (now: Date): { start: Date; end: Date } => {
  const start = new Date(now);
  const weekday = (start.getDay() + 6) % 7;
  start.setDate(start.getDate() - weekday);
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setDate(end.getDate() + 7);
  return { start, end };
};

export const isSameDay = (a: Date, b: Date): boolean =>
  a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();

/** Money the driver should already have made at this point of the shift. */
export const paceTargetMxn = (group: ShiftGroup, elapsedMinutes: number): number => {
  const goals = goalsFor(group);
  const workedHours = Math.min(8, Math.max(0, elapsedMinutes / 60));
  return Math.round(goals.hourlyMxn * workedHours);
};

export interface AssignmentCheckInput {
  driver: Driver;
  vehicle: Vehicle;
  now: Date;
  odometerKm: number;
  batteryPct: number;
}

/**
 * Every blocking rule from the operations manual, evaluated in priority order.
 * An empty array means the unit can be assigned.
 */
export const validateAssignment = ({
  driver,
  vehicle,
  now,
  odometerKm,
  batteryPct,
}: AssignmentCheckInput): AssignmentIssue[] => {
  const issues: AssignmentIssue[] = [];

  if (vehicle.stationId !== driver.stationId) {
    issues.push({
      code: "other_station",
      message: "Unidad de otra estación, no puedes iniciar labores aquí",
    });
  }

  if (vehicle.status === "occupied" || (vehicle.occupiedBy !== null && vehicle.occupiedBy !== driver.id)) {
    issues.push({ code: "vehicle_occupied", message: "Vehículo ocupado, notificar a supervisor" });
  }

  if (!isCorrectShiftMoment(driver, now)) {
    issues.push({ code: "invalid_shift", message: "Turno inválido, notificar a supervisor" });
  }

  if (!driver.authorizedVehicleIds.includes(vehicle.id)) {
    issues.push({
      code: "not_authorized",
      message: "No tienes autorizado usar esta unidad, notificar a supervisor",
    });
  }

  if (batteryPct <= MIN_BATTERY_PCT) {
    issues.push({
      code: "low_battery",
      message: "Batería insuficiente para iniciar turno, notificar a supervisor",
    });
  }

  if (Math.round(odometerKm) !== Math.round(vehicle.odometerKm)) {
    issues.push({
      code: "odometer_mismatch",
      message: "Discrepancia con el kilometraje registrado, notificar a supervisor",
    });
  }

  return issues;
};
