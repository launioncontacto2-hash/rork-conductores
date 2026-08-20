import type { CreditAccount, CreditPayment } from "@/lib/types";

/** Terms of the fleet's used-unit credit program. */
export const CREDIT_PROGRAM = {
  vehicleModel: "BYD Dolphin Mini",
  /** Internal figure used only for calculations; never shown in the marketing banner. */
  priceMxn: 390_000,
  downPaymentMxn: 0,
  termMonths: 48,
  termWeeks: 192,
  /** 390,000 / 192 weekly instalments, rounded to the peso. */
  weeklyMxn: 2_031,
  /** The unit stays in the fleet while the driver builds credit behaviour. */
  deliveryMonth: 24,
  minHandoverKm: 110_000,
  maxHandoverKm: 120_000,
  imageUrl: "/credit-vehicle.png",
  videoUrl: "/credit-explainer.mp4",
  narrationUrl: "/credit-narration.mp3",
} as const;

export interface CreditBenefit {
  id: string;
  title: string;
  detail: string;
}

export const CREDIT_BENEFITS: CreditBenefit[] = [
  { id: "down", title: "Sin enganche", detail: "Arrancas tu crédito sin pago inicial" },
  { id: "approval", title: "Aprobación inmediata", detail: "Se firma el mismo día en la estación" },
  { id: "charger", title: "Equipo de carga incluido", detail: "Cargador portátil para tu domicilio" },
  { id: "km", title: "Máximo 120,000 km", detail: "La unidad sale de flotilla entre 110 y 120 mil km" },
  { id: "year", title: "Se entrega unidad del año", detail: "Modelo reciente, seminueva certificada" },
  { id: "term", title: "Plazo de 48 meses", detail: "192 pagos semanales vía nómina" },
];

export interface CreditStep {
  index: number;
  title: string;
  detail: string;
}

export const CREDIT_STEPS: CreditStep[] = [
  { index: 1, title: "Firma de contrato", detail: "Sin enganche y con aprobación inmediata" },
  { index: 2, title: "Descuento semanal", detail: "Tu abono se descuenta cada semana vía nómina" },
  {
    index: 3,
    title: "Comportamiento crediticio",
    detail: "Riesgo bajo, precio bajo: tu cumplimiento define tus condiciones",
  },
  { index: 4, title: "Entrega en el mes 24", detail: "La unidad permanece en flotilla hasta que la recibes" },
];

export const CREDIT_SCRIPT =
  "Los créditos tradicionales incorporan el costo del riesgo en el precio final del vehículo. Nuestro programa funciona de manera diferente. Durante los primeros 24 meses la unidad permanece dentro de la flotilla mientras construyes tu historial de cumplimiento. Ese modelo nos permite reducir costos y ofrecerte mejores condiciones de financiamiento.";

export interface CreditCaption {
  start: number;
  text: string;
}

/** Captions synced with the narration track. */
export const CREDIT_CAPTIONS: CreditCaption[] = [
  { start: 0, text: "Los créditos tradicionales incorporan el costo del riesgo en el precio final del vehículo." },
  { start: 7, text: "Nuestro programa funciona de manera diferente." },
  {
    start: 11.1,
    text: "Durante los primeros 24 meses la unidad permanece en la flotilla mientras construyes tu historial de cumplimiento.",
  },
  { start: 20.4, text: "Ese modelo reduce costos y te da mejores condiciones de financiamiento." },
];

export type CreditRisk = "low" | "medium" | "high";

export const CREDIT_RISK_LABEL: Record<CreditRisk, string> = {
  low: "Bajo",
  medium: "Medio",
  high: "Alto",
};

export const CREDIT_RISK_DETAIL: Record<CreditRisk, string> = {
  low: "Riesgo bajo: conservas las mejores condiciones del programa.",
  medium: "Un atraso más y tu perfil sube a riesgo alto.",
  high: "Riesgo alto: la entrega de la unidad puede posponerse.",
};

export interface CreditMetrics {
  weeksPaid: number;
  weeksRemaining: number;
  paidMxn: number;
  balanceMxn: number;
  paymentProgress: number;
  nextPayment: CreditPayment | null;
  complianceRate: number;
  risk: CreditRisk;
  monthsElapsed: number;
  monthsToDelivery: number;
  deliveryProgress: number;
  estimatedDeliveryDate: Date;
  contractEndDate: Date;
  kmToHandover: number;
  isUnitDelivered: boolean;
}

const addMonths = (date: Date, months: number): Date => {
  const result = new Date(date);
  result.setMonth(result.getMonth() + months);
  return result;
};

const monthsBetween = (from: Date, to: Date): number => {
  const months = (to.getFullYear() - from.getFullYear()) * 12 + (to.getMonth() - from.getMonth());
  return to.getDate() >= from.getDate() ? months : months - 1;
};

/** Derives the transparent contract metrics for a given moment. */
export const creditMetrics = (account: CreditAccount, now: Date): CreditMetrics => {
  const startedAt = new Date(account.startedAt);
  const monthsElapsed = Math.max(0, monthsBetween(startedAt, now));
  const evaluated = account.onTimePayments + account.latePayments;
  const compliance = evaluated > 0 ? account.onTimePayments / evaluated : 1;
  const risk: CreditRisk = account.latePayments === 0 ? "low" : account.latePayments <= 2 ? "medium" : "high";
  const pending = account.payments
    .filter((payment) => payment.status !== "paid")
    .sort((a, b) => new Date(a.dueDate).getTime() - new Date(b.dueDate).getTime());

  return {
    weeksPaid: account.weeksPaid,
    weeksRemaining: Math.max(0, CREDIT_PROGRAM.termWeeks - account.weeksPaid),
    paidMxn: account.paidMxn,
    balanceMxn: Math.max(0, account.totalMxn - account.paidMxn),
    paymentProgress: account.totalMxn > 0 ? account.paidMxn / account.totalMxn : 0,
    nextPayment: pending[0] ?? null,
    complianceRate: compliance,
    risk,
    monthsElapsed,
    monthsToDelivery: Math.max(0, CREDIT_PROGRAM.deliveryMonth - monthsElapsed),
    deliveryProgress: Math.min(1, monthsElapsed / CREDIT_PROGRAM.deliveryMonth),
    estimatedDeliveryDate: addMonths(startedAt, CREDIT_PROGRAM.deliveryMonth),
    contractEndDate: addMonths(startedAt, CREDIT_PROGRAM.termMonths),
    kmToHandover: Math.max(0, CREDIT_PROGRAM.minHandoverKm - account.assignedVehicleOdometerKm),
    isUnitDelivered: monthsElapsed >= CREDIT_PROGRAM.deliveryMonth,
  };
};

/** Fresh contract signed today: no down payment, first instalment in a week. */
export const newCreditAccount = (now: Date, vehicleInternalNumber: string): CreditAccount => ({
  contractId: `CR-${Math.floor(now.getTime() / 1000) % 100_000}`,
  vehicleTarget: `${CREDIT_PROGRAM.vehicleModel} · ${vehicleInternalNumber}`,
  startedAt: now.toISOString(),
  totalMxn: CREDIT_PROGRAM.priceMxn,
  paidMxn: 0,
  weeklyMxn: CREDIT_PROGRAM.weeklyMxn,
  weeksPaid: 0,
  onTimePayments: 0,
  latePayments: 0,
  assignedVehicleOdometerKm: 96_480,
  payments: [
    {
      id: "cp-new-1",
      concept: "Abono semanal 1",
      dueDate: new Date(now.getTime() + 7 * 86_400_000).toISOString(),
      amountMxn: CREDIT_PROGRAM.weeklyMxn,
      status: "due",
    },
  ],
});
