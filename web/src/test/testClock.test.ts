import {
  currentTestInstant,
  makePausedClockCommand,
  stationDateTimeInputValue,
  stationDateTimeToISOString,
  type TestClockRow,
} from "@/console/testClock";

const clock: TestClockRow = {
  environment_id: "9f8d4a52-0f0e-4a3f-9a1e-2c6f5b8d7e10",
  anchor_simulated_at: "2026-08-31T08:05:00.000Z",
  anchor_real_at: "2026-08-31T08:00:00.000Z",
  speed: 10,
  is_paused: true,
  revision: 42,
  updated_at: "2026-08-31T08:00:00.000Z",
};

describe("TEST clock helpers", () => {
  it("keeps a paused clock on its simulated anchor", () => {
    expect(currentTestInstant(clock, new Date("2026-08-31T12:00:00.000Z")).toISOString())
      .toBe("2026-08-31T08:05:00.000Z");
  });

  it("derives a running simulated instant from elapsed real time and speed", () => {
    const running = { ...clock, is_paused: false };
    expect(currentTestInstant(running, new Date("2026-08-31T08:03:00.000Z")).toISOString())
      .toBe("2026-08-31T08:35:00.000Z");
  });

  it("round-trips a Puebla wall-clock value without using the browser time zone", () => {
    const absolute = stationDateTimeToISOString("2026-08-31T04:55:00", "America/Mexico_City");
    expect(absolute).toBe("2026-08-31T10:55:00.000Z");
    expect(stationDateTimeInputValue(new Date(absolute), "America/Mexico_City"))
      .toBe("2026-08-31T04:55:00");
  });

  it("builds an optimistic supervisor RPC that pauses the selected instant", () => {
    expect(makePausedClockCommand(
      clock,
      "2026-08-31T04:55:00",
      "America/Mexico_City",
      new Date("2026-09-01T14:00:00.000Z"),
    )).toEqual({
      p_environment_id: clock.environment_id,
      p_anchor_simulated_at: "2026-08-31T10:55:00.000Z",
      p_anchor_real_at: "2026-09-01T14:00:00.000Z",
      p_speed: 10,
      p_is_paused: true,
      p_expected_revision: 42,
    });
  });
});
