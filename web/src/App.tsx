import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { type ReactNode } from "react";
import { BrowserRouter, Navigate, Outlet, Route, Routes } from "react-router-dom";

import { AppShell } from "@/components/AppShell";
import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { ConsoleAuthProvider, useConsoleAuth } from "@/console/ConsoleAuth";
import { ROLE, type StaffRole } from "@/lib/org";
import { FleetProvider, useFleet } from "@/store/fleet";

import Asignar from "./pages/Asignar";
import Avisos from "./pages/Avisos";
import Bonos from "./pages/Bonos";
import Credito from "./pages/Credito";
import Finalizar from "./pages/Finalizar";
import Historial from "./pages/Historial";
import Incidencia from "./pages/Incidencia";
import Ingreso from "./pages/Ingreso";
import Inspeccion from "./pages/Inspeccion";
import Login from "./pages/Login";
import Metas from "./pages/Metas";
import NotFound from "./pages/NotFound";
import OperationsConsole from "./pages/OperationsConsole";
import RoleWorkspace from "./pages/RoleWorkspace";
import Turno from "./pages/Turno";

const queryClient = new QueryClient();

/** Sends every session to the landing screen of its own role. */
const RoleGate = ({ role, children }: { role: StaffRole; children: ReactNode }) => {
  const { session } = useFleet();
  if (!session) return <Navigate to="/" replace />;
  if (session.role !== role) return <Navigate to={ROLE[session.role].home} replace />;
  return <>{children}</>;
};

/** Driver interface: the operational tabs live behind a driver session only. */
const DriverShell = () => (
  <RoleGate role="driver">
    <AppShell>
      <Outlet />
    </AppShell>
  </RoleGate>
);

const LoginGate = () => {
  const { session } = useFleet();
  const { identity } = useConsoleAuth();
  if (identity) return <Navigate to="/console" replace />;
  return session ? <Navigate to={ROLE[session.role].home} replace /> : <Login />;
};

const ConsoleGate = () => {
  const { identity } = useConsoleAuth();
  return identity ? <OperationsConsole /> : <Navigate to="/" replace />;
};

const App = () => (
  <QueryClientProvider client={queryClient}>
    <FleetProvider>
      <ConsoleAuthProvider>
        <TooltipProvider>
          <Toaster position="top-center" />
          <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
            <Routes>
            <Route path="/" element={<LoginGate />} />
            <Route path="/console" element={<ConsoleGate />} />
            <Route element={<DriverShell />}>
              <Route path="/turno" element={<Turno />} />
              <Route path="/metas" element={<Metas />} />
              <Route path="/bonos" element={<Bonos />} />
              <Route path="/credito" element={<Credito />} />
              <Route path="/historial" element={<Historial />} />
              <Route path="/avisos" element={<Avisos />} />
              <Route path="/asignar" element={<Asignar />} />
              <Route path="/inspeccion" element={<Inspeccion />} />
              <Route path="/ingreso" element={<Ingreso />} />
              <Route path="/incidencia" element={<Incidencia />} />
              <Route path="/finalizar" element={<Finalizar />} />
            </Route>
            <Route
              path="/supervision"
              element={
                <RoleGate role="supervisor">
                  <RoleWorkspace />
                </RoleGate>
              }
            />
            <Route
              path="/gerencia"
              element={
                <RoleGate role="manager">
                  <RoleWorkspace />
                </RoleGate>
              }
            />
            <Route
              path="/mantenimiento"
              element={
                <RoleGate role="maintenance">
                  <RoleWorkspace />
                </RoleGate>
              }
            />
            <Route
              path="/direccion"
              element={
                <RoleGate role="national">
                  <RoleWorkspace />
                </RoleGate>
              }
            />
            <Route path="*" element={<NotFound />} />
            </Routes>
          </BrowserRouter>
        </TooltipProvider>
      </ConsoleAuthProvider>
    </FleetProvider>
  </QueryClientProvider>
);

export default App;
