/** Locale helpers — the product is Spanish (MX) only. */

const currency = new Intl.NumberFormat("es-MX", {
  style: "currency",
  currency: "MXN",
  maximumFractionDigits: 0,
});

const currencyExact = new Intl.NumberFormat("es-MX", {
  style: "currency",
  currency: "MXN",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

export const mxn = (value: number): string => currency.format(Math.round(value));
export const mxnExact = (value: number): string => currencyExact.format(value);

export const km = (value: number): string => `${new Intl.NumberFormat("es-MX").format(Math.round(value))} km`;

/** 05:07 style clock, always from a real Date. */
export const clock = (date: Date): string =>
  date.toLocaleTimeString("es-MX", { hour: "2-digit", minute: "2-digit", hour12: false });

export const clockSeconds = (date: Date): string =>
  date.toLocaleTimeString("es-MX", { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false });

export const dateLong = (date: Date): string =>
  date.toLocaleDateString("es-MX", { weekday: "long", day: "numeric", month: "long" });

export const dateShort = (date: Date): string =>
  date.toLocaleDateString("es-MX", { weekday: "short", day: "2-digit", month: "short" });

/** "12 ago" for the bonus week ranges. */
export const dayNumber = (date: Date): string =>
  date.toLocaleDateString("es-MX", { day: "numeric", month: "short" }).replace(".", "");

export const monthLong = (date: Date): string => {
  const raw = date.toLocaleDateString("es-MX", { month: "long", year: "numeric" });
  return raw.charAt(0).toUpperCase() + raw.slice(1);
};

export const rating = (value: number): string =>
  new Intl.NumberFormat("es-MX", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value);

export const dayShort = (date: Date): string => {
  const raw = date.toLocaleDateString("es-MX", { weekday: "short" }).replace(".", "");
  return raw.charAt(0).toUpperCase() + raw.slice(1, 3);
};

/** 7h 32m — for durations shown as text. */
export const durationText = (minutes: number): string => {
  const total = Math.max(0, Math.round(minutes));
  const h = Math.floor(total / 60);
  const m = total % 60;
  return h > 0 ? `${h}h ${String(m).padStart(2, "0")}m` : `${m}m`;
};

/** 07:32:11 — for the live elapsed counter. */
export const stopwatch = (seconds: number): string => {
  const total = Math.max(0, Math.floor(seconds));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  return [h, m, s].map((part) => String(part).padStart(2, "0")).join(":");
};

/** 01:15 — late time is always communicated as hh:mm. */
export const lateText = (minutes: number): string => {
  const total = Math.max(0, Math.round(minutes));
  const h = Math.floor(total / 60);
  const m = total % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
};

export const firstName = (fullName: string): string => fullName.trim().split(" ")[0] ?? fullName;

export const relativeTime = (iso: string, now: Date): string => {
  const diffMinutes = Math.round((now.getTime() - new Date(iso).getTime()) / 60000);
  if (diffMinutes < 1) return "ahora";
  if (diffMinutes < 60) return `hace ${diffMinutes} min`;
  if (diffMinutes < 60 * 24) return `hace ${Math.floor(diffMinutes / 60)} h`;
  const days = Math.floor(diffMinutes / (60 * 24));
  return days === 1 ? "ayer" : `hace ${days} días`;
};
