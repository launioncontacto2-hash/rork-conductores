import { render } from "vitest-browser-react";

import App from "@/App";

test("exposes the real DORI console access without demonstration shortcuts", async () => {
  window.history.replaceState({}, "", "/");
  const screen = await render(<App />);

  await expect.element(screen.getByText("DORI", { exact: true })).toBeInTheDocument();
  await expect.element(screen.getByText("Consola de operación")).toBeInTheDocument();
  await expect.element(screen.getByRole("button", { name: "Identificar y entrar" })).toBeInTheDocument();
  await expect.element(screen.getByText("Cuentas de demostración")).not.toBeInTheDocument();
});
