import { render } from "vitest-browser-react";

import App from "@/App";

test("exposes the real DORI console access without demonstration shortcuts", async () => {
  window.history.replaceState({}, "", "/");
  const screen = await render(<App />);

  await expect.element(screen.getByText("DORI", { exact: true })).toBeInTheDocument();
  await expect.element(screen.getByText("La movilidad del futuro")).toBeInTheDocument();
  await expect.element(screen.getByPlaceholder("Correo", { exact: true })).toBeInTheDocument();
  await expect.element(screen.getByPlaceholder("Contraseña", { exact: true })).toBeInTheDocument();
  await expect.element(screen.getByRole("button", { name: "Iniciar sesión" })).toBeInTheDocument();
  await expect.element(screen.getByText("No puedo acceder")).toBeInTheDocument();
  await expect.element(screen.getByText("Entorno de pruebas · Consola DORI")).toBeInTheDocument();
  await expect.element(screen.getByText("Supabase verificará tu cuenta", { exact: false })).not.toBeInTheDocument();
  await expect.element(screen.getByText("Cuentas de demostración")).not.toBeInTheDocument();
});
