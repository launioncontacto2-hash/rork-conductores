import { CREDIT_PROGRAM } from "./credit";
import { goalsFor, groupForDate, scheduledStart, TRIPS_GOAL_PER_DAY } from "./schedule";
import type {
  CreditAccount,
  Driver,
  IncomeEntry,
  Incident,
  Notice,
  ShiftRecord,
  SupervisorReport,
  Vehicle,
} from "./types";

/** Simulated backend. Swap these builders for API calls when the fleet backend lands. */

export const MOCK_DRIVER: Driver = {
  id: "drv-1042",
  name: "Carlos Méndez Rivas",
  employeeNumber: "EV-1042",
  email: "launion.contacto2@gmail.com",
  password: "Kymyly14",
  photoUrl: "/driver-portrait.jpg",
  stationId: "est-nte-cdmx",
  station: "Estación Norte · CDMX",
  shift: { group: "weekday", slot: "morning" },
  authorizedVehicleIds: ["veh-014", "veh-027", "veh-055"],
};

export const MOCK_VEHICLES: Vehicle[] = [
  {
    id: "veh-014",
    qrCode: "TEV-014",
    internalNumber: "TEV-014",
    model: "BYD Dolphin Mini 2025",
    plates: "NXP-482-C",
    odometerKm: 42180,
    batteryPct: 96,
    stationId: "est-nte-cdmx",
    station: "Estación Norte · CDMX",
    status: "available",
    occupiedBy: null,
    photoUrl: "/vehicle-photo.jpg",
  },
  {
    id: "veh-027",
    qrCode: "TEV-027",
    internalNumber: "TEV-027",
    model: "Nissan Leaf 2024",
    plates: "PLC-733-B",
    odometerKm: 61540,
    batteryPct: 88,
    stationId: "est-nte-cdmx",
    station: "Estación Norte · CDMX",
    status: "available",
    occupiedBy: null,
    photoUrl: "/vehicle-photo.jpg",
  },
  {
    id: "veh-031",
    qrCode: "TEV-031",
    internalNumber: "TEV-031",
    model: "BYD Dolphin 2025",
    plates: "MRK-118-A",
    odometerKm: 30210,
    batteryPct: 79,
    stationId: "est-nte-cdmx",
    station: "Estación Norte · CDMX",
    status: "occupied",
    occupiedBy: "drv-2210",
    photoUrl: "/vehicle-photo.jpg",
  },
  {
    id: "veh-042",
    qrCode: "TEV-042",
    internalNumber: "TEV-042",
    model: "JAC E10X 2024",
    plates: "TQD-905-D",
    odometerKm: 25780,
    batteryPct: 62,
    stationId: "est-sur-cdmx",
    station: "Estación Sur · CDMX",
    status: "available",
    occupiedBy: null,
    photoUrl: "/vehicle-photo.jpg",
  },
  {
    id: "veh-055",
    qrCode: "TEV-055",
    internalNumber: "TEV-055",
    model: "BYD Yuan Plus 2025",
    plates: "VZR-260-E",
    odometerKm: 18940,
    batteryPct: 91,
    stationId: "est-nte-cdmx",
    station: "Estación Norte · CDMX",
    status: "available",
    occupiedBy: null,
    photoUrl: "/vehicle-photo.jpg",
  },
  {
    id: "veh-063",
    qrCode: "TEV-063",
    internalNumber: "TEV-063",
    model: "BYD Dolphin Mini 2025",
    plates: "WBN-347-F",
    odometerKm: 12360,
    batteryPct: 45,
    stationId: "est-nte-cdmx",
    station: "Estación Norte · CDMX",
    status: "maintenance",
    occupiedBy: null,
    photoUrl: "/vehicle-photo.jpg",
  },
];

const LATE_PATTERN = [15, 0, 10, 0, 0, 20, 0, 5, 0, 12, 0, 0, 18, 0];
const EARNINGS_FACTOR = [1.04, 0.92, 1.0, 1.12, 0.88, 0.97, 1.06, 0.91, 1.08, 0.95, 1.01, 0.86, 1.1, 0.99];
const TRIPS_PATTERN = [15, 12, 14, 16, 11, 14, 15, 13, 14, 12, 14, 10, 16, 14];

const dayOffset = (now: Date, days: number): Date => {
  const day = new Date(now);
  day.setDate(day.getDate() - days);
  return day;
};

/** Closed shifts covering the whole current month, honoring the driver's shift group. */
export const buildShiftHistory = (driver: Driver, now: Date): ShiftRecord[] => {
  const records: ShiftRecord[] = [];
  let odometer = 42180;
  let index = 0;

  for (let back = 45; back >= 1; back -= 1) {
    const day = dayOffset(now, back);
    if (groupForDate(day) !== driver.shift.group) continue;

    const late = LATE_PATTERN[index % LATE_PATTERN.length];
    const trips = TRIPS_PATTERN[index % TRIPS_PATTERN.length];
    const goals = goalsFor(driver.shift.group);
    const earnings = Math.round(goals.dailyMxn * EARNINGS_FACTOR[index % EARNINGS_FACTOR.length]);
    const scheduled = scheduledStart(driver.shift.slot, day);
    const started = new Date(scheduled.getTime() + late * 60000);
    const ended = new Date(started.getTime() + (9 * 60 - Math.min(late, 30)) * 60000);
    const kmDriven = 150 + ((index * 17) % 60);
    const startOdometer = odometer;
    odometer += kmDriven;

    records.push({
      id: `shift-h-${back}`,
      driverId: driver.id,
      vehicleId: "veh-014",
      vehicleInternalNumber: "TEV-014",
      group: driver.shift.group,
      slot: driver.shift.slot,
      scheduledStartAt: scheduled.toISOString(),
      startedAt: started.toISOString(),
      endedAt: ended.toISOString(),
      lateMinutes: late,
      paidBackMinutes: index % 5 === 0 ? Math.min(late, 10) : 0,
      startOdometerKm: startOdometer,
      endOdometerKm: startOdometer + kmDriven,
      startBatteryPct: 92 - (index % 4) * 3,
      endBatteryPct: 24 + (index % 5) * 4,
      trips,
      earningsMxn: earnings,
      photos: {},
    });
    index += 1;
  }

  return records.reverse();
};

/** The odometer of the most recent closed shift becomes the expected reading. */
export const syncVehicleOdometers = (vehicles: Vehicle[], history: ShiftRecord[]): Vehicle[] =>
  vehicles.map((vehicle) => {
    const last = history.find((record) => record.vehicleId === vehicle.id);
    return last ? { ...vehicle, odometerKm: last.endOdometerKm } : vehicle;
  });

export const buildIncomeHistory = (driver: Driver, history: ShiftRecord[]): IncomeEntry[] =>
  history.map((record, index) => ({
    id: `inc-${record.id}`,
    driverId: driver.id,
    shiftId: record.id,
    date: record.endedAt,
    amountMxn: record.earningsMxn,
    trips: record.trips,
    platform: index % 3 === 0 ? "DiDi" : "Uber",
    note: record.trips < TRIPS_GOAL_PER_DAY ? "Día con baja demanda" : undefined,
  }));

export const buildIncidents = (driver: Driver, now: Date): Incident[] => [
  {
    id: "inci-002",
    driverId: driver.id,
    vehicleId: "veh-014",
    vehicleInternalNumber: "TEV-014",
    kind: "damage",
    createdAt: dayOffset(now, 3).toISOString(),
    description: "Rayón en salpicadera trasera derecha al salir del estacionamiento de la estación.",
    photos: [],
    status: "review",
  },
  {
    id: "inci-001",
    driverId: driver.id,
    vehicleId: "veh-027",
    vehicleInternalNumber: "TEV-027",
    kind: "mechanical",
    createdAt: dayOffset(now, 9).toISOString(),
    description: "Sensor de proximidad trasero intermitente, alarma se activa sin obstáculos.",
    photos: [],
    status: "closed",
  },
];

export const buildNotices = (now: Date): Notice[] => {
  const hoursAgo = (hours: number): string => new Date(now.getTime() - hours * 3600000).toISOString();
  return [
    {
      id: "not-005",
      kind: "reminder",
      title: "Recuerda cargar al 100% antes de entregar",
      body: "La unidad debe quedar conectada al cargador de la bahía asignada al terminar tu turno.",
      createdAt: hoursAgo(1),
      read: false,
    },
    {
      id: "not-004",
      kind: "maintenance",
      title: "Mantenimiento programado · TEV-014",
      body: "Servicio de 40,000 km el viernes a las 15:00 en Estación Norte. Entrega la unidad 30 min antes.",
      createdAt: hoursAgo(6),
      read: false,
    },
    {
      id: "not-003",
      kind: "credit",
      title: "Pago de crédito por vencer",
      body: "Tu abono semanal de $1,200 se aplica el domingo. Saldo restante $46,800.",
      createdAt: hoursAgo(20),
      read: false,
    },
    {
      id: "not-002",
      kind: "station",
      title: "Aviso de estación · Bahía 4 cerrada",
      body: "La bahía 4 estará fuera de servicio por instalación de cargador rápido. Usa bahías 1 a 3.",
      createdAt: hoursAgo(30),
      read: true,
    },
    {
      id: "not-001",
      kind: "reminder",
      title: "Revisión de llantas quincenal",
      body: "Reporta presión y desgaste en el reporte de incidencias si detectas algo fuera de rango.",
      createdAt: hoursAgo(52),
      read: true,
    },
  ];
};

/** Supervisor reports drive the cleanliness / vehicle-care bonus. */
export const buildSupervisorReports = (now: Date): SupervisorReport[] => [
  {
    id: "sup-001",
    kind: "cleanliness",
    createdAt: dayOffset(now, 41).toISOString(),
    vehicleInternalNumber: "TEV-014",
    note: "Interiores con basura al entregar la unidad. Se descontó el bono del mes anterior.",
  },
];

/** Mid-term contract (week 14 of 192) used to show every metric of the credit panel. */
export const buildCreditAccount = (now: Date): CreditAccount => {
  const dayIn = (days: number): string => {
    const date = new Date(now);
    date.setDate(date.getDate() + days);
    return date.toISOString();
  };
  const weekly = CREDIT_PROGRAM.weeklyMxn;
  const weeksPaid = 14;
  return {
    contractId: "CR-10428",
    vehicleTarget: `${CREDIT_PROGRAM.vehicleModel} · TEV-014`,
    startedAt: dayIn(-98),
    totalMxn: CREDIT_PROGRAM.priceMxn,
    paidMxn: weekly * weeksPaid,
    weeklyMxn: weekly,
    weeksPaid,
    onTimePayments: 13,
    latePayments: 1,
    assignedVehicleOdometerKm: 96_480,
    payments: [
      { id: "cp-15", concept: "Abono semanal 15", dueDate: dayIn(4), amountMxn: weekly, status: "due" },
      { id: "cp-14", concept: "Abono semanal 14", dueDate: dayIn(-3), amountMxn: weekly, status: "paid" },
      { id: "cp-13", concept: "Abono semanal 13", dueDate: dayIn(-10), amountMxn: weekly, status: "paid" },
      { id: "cp-12", concept: "Abono semanal 12", dueDate: dayIn(-17), amountMxn: weekly, status: "paid" },
      { id: "cp-11", concept: "Abono semanal 11", dueDate: dayIn(-24), amountMxn: weekly, status: "late" },
      { id: "cp-10", concept: "Abono semanal 10", dueDate: dayIn(-31), amountMxn: weekly, status: "paid" },
    ],
  };
};
