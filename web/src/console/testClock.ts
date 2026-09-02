export const SHARED_TEST_ENVIRONMENT_ID = "9f8d4a52-0f0e-4a3f-9a1e-2c6f5b8d7e10";

export interface TestClockRow {
  environment_id: string;
  anchor_simulated_at: string;
  anchor_real_at: string;
  speed: number;
  is_paused: boolean;
  revision: number;
  updated_at: string;
}

export interface TestClockCommand {
  p_environment_id: string;
  p_anchor_simulated_at: string;
  p_anchor_real_at: string;
  p_speed: number;
  p_is_paused: boolean;
  p_expected_revision: number;
}

const numericParts = (date: Date, timeZone: string) => {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date);

  return Object.fromEntries(
    parts
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, Number(part.value)]),
  ) as Record<"year" | "month" | "day" | "hour" | "minute" | "second", number>;
};

const pad = (value: number) => String(value).padStart(2, "0");

export const currentTestInstant = (clock: TestClockRow, realNow = new Date()) => {
  const simulatedAnchor = new Date(clock.anchor_simulated_at);
  if (clock.is_paused) return simulatedAnchor;
  const elapsed = realNow.getTime() - new Date(clock.anchor_real_at).getTime();
  return new Date(simulatedAnchor.getTime() + elapsed * clock.speed);
};

/** Formats an absolute instant for an HTML datetime-local input in station time. */
export const stationDateTimeInputValue = (date: Date, timeZone: string) => {
  const part = numericParts(date, timeZone);
  return `${part.year}-${pad(part.month)}-${pad(part.day)}T${pad(part.hour)}:${pad(part.minute)}:${pad(part.second)}`;
};

/**
 * Converts a wall-clock value from the station's IANA time zone into an absolute instant.
 * The short iteration also handles zones whose UTC offset changes with daylight saving.
 */
export const stationDateTimeToISOString = (value: string, timeZone: string) => {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(value);
  if (!match) throw new Error("Selecciona una fecha y hora válidas.");

  const [, year, month, day, hour, minute, second = "00"] = match;
  const wallUtc = Date.UTC(+year, +month - 1, +day, +hour, +minute, +second);
  let candidate = wallUtc;

  for (let attempt = 0; attempt < 3; attempt += 1) {
    const part = numericParts(new Date(candidate), timeZone);
    const renderedAsUtc = Date.UTC(part.year, part.month - 1, part.day, part.hour, part.minute, part.second);
    const offset = renderedAsUtc - candidate;
    candidate = wallUtc - offset;
  }

  return new Date(candidate).toISOString();
};

export const makePausedClockCommand = (
  clock: TestClockRow,
  targetLocalValue: string,
  timeZone: string,
  realNow = new Date(),
): TestClockCommand => ({
  p_environment_id: clock.environment_id,
  p_anchor_simulated_at: stationDateTimeToISOString(targetLocalValue, timeZone),
  p_anchor_real_at: realNow.toISOString(),
  p_speed: clock.speed > 0 ? clock.speed : 1,
  p_is_paused: true,
  p_expected_revision: clock.revision,
});
