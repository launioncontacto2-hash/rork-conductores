import { render } from "vitest-browser-react";

import { TestClockDialog } from "@/console/TestClockDialog";
import type { TestClockRow } from "@/console/testClock";

const clock: TestClockRow = {
  environment_id: "9f8d4a52-0f0e-4a3f-9a1e-2c6f5b8d7e10",
  anchor_simulated_at: "2026-08-31T10:55:00.000Z",
  anchor_real_at: "2026-08-31T10:55:00.000Z",
  speed: 1,
  is_paused: true,
  revision: 43,
  updated_at: "2026-08-31T10:55:00.000Z",
};

test("opens the supervisor TEST clock with the station instant prefilled", async () => {
  const screen = await render(
    <TestClockDialog
      clock={clock}
      stationTimeZone="America/Mexico_City"
      onApplied={async () => undefined}
    />,
  );

  await screen.getByRole("button", { name: "Ajustar reloj TEST" }).click();

  await expect.element(screen.getByRole("dialog")).toBeInTheDocument();
  await expect.element(screen.getByLabelText("Fecha y hora de estación"))
    .toHaveValue("2026-08-31T04:55");
  await expect.element(screen.getByRole("button", { name: "Aplicar y pausar" })).toBeEnabled();
});
