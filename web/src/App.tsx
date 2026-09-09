import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";

import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { ConsoleAuthProvider, useConsoleAuth } from "@/console/ConsoleAuth";

import Login from "./pages/Login";
import NotFound from "./pages/NotFound";
import OperationsConsole from "./pages/OperationsConsole";

const queryClient = new QueryClient();

const LoginGate = () => {
  const { identity } = useConsoleAuth();
  if (identity) return <Navigate to="/console" replace />;
  return <Login />;
};

const ConsoleGate = () => {
  const { identity } = useConsoleAuth();
  return identity ? <OperationsConsole /> : <Navigate to="/" replace />;
};

const App = () => (
  <QueryClientProvider client={queryClient}>
    <ConsoleAuthProvider>
      <TooltipProvider>
        <Toaster position="top-center" />
        <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
          <Routes>
            <Route path="/" element={<LoginGate />} />
            <Route path="/console" element={<ConsoleGate />} />
            <Route path="*" element={<NotFound />} />
          </Routes>
        </BrowserRouter>
      </TooltipProvider>
    </ConsoleAuthProvider>
  </QueryClientProvider>
);

export default App;
