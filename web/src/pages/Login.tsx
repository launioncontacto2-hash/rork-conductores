import { KeyRound, Loader2, LockKeyhole, Mail, ShieldCheck, Zap } from "lucide-react";
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { toast } from "sonner";

import { BigButton } from "@/components/Pieces";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { useConsoleAuth } from "@/console/ConsoleAuth";

/**
 * The only access door for Consola DORI. Supabase Auth proves the credential and
 * console_identity then proves the active supervisor membership and station scope.
 * There is deliberately no local directory, biometric shortcut or simulated recovery.
 */
const Login = () => {
  const { accessMessage, isResolving, signInSupervisor } = useConsoleAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isRecoveryOpen, setIsRecoveryOpen] = useState(false);

  const submitCredentials = async (): Promise<void> => {
    setError(null);
    try {
      await signInSupervisor(email.trim(), password);
      setPassword("");
      toast.success("Acceso autorizado", { description: "Abriendo tu estación en Consola DORI." });
      navigate("/console", { replace: true });
    } catch (reason) {
      const message = reason instanceof Error ? reason.message : "No fue posible abrir Consola DORI.";
      setPassword("");
      setError(message);
      toast.error("Acceso denegado", { description: message });
    }
  };

  return (
    <div className="station-bg flex min-h-dvh flex-col justify-between px-6 py-10">
      <div className="mx-auto w-full max-w-md">
        <div className="flex items-center gap-3">
          <span className="grid size-12 place-items-center rounded-2xl bg-primary/15 text-primary volt-glow">
            <Zap className="size-7" strokeWidth={2.6} />
          </span>
          <div>
            <p className="text-xl font-black leading-none tracking-tight">DORI</p>
            <p className="label-caps mt-1">Consola de operación</p>
          </div>
        </div>
      </div>

      <main className="mx-auto w-full max-w-md animate-rise-in">
        <div className="mb-8 grid size-20 place-items-center rounded-[1.75rem] border border-primary/30 bg-primary/10 text-primary volt-glow">
          <ShieldCheck className="size-10" strokeWidth={1.7} />
        </div>
        <h1 className="text-3xl font-black tracking-tight">Identifícate</h1>
        <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
          Supabase verificará tu cuenta, tu rol de supervisión y la estación que puedes coordinar.
        </p>

        <form
          className="mt-7 space-y-3"
          onSubmit={(event) => {
            event.preventDefault();
            void submitCredentials();
          }}
        >
          <div className="relative">
            <Mail className="pointer-events-none absolute left-4 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="Correo institucional"
              type="email"
              autoComplete="email"
              autoCapitalize="none"
              spellCheck={false}
              className="h-14 rounded-2xl pl-11 text-base"
            />
          </div>
          <div className="relative">
            <LockKeyhole className="pointer-events-none absolute left-4 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder="Contraseña"
              type="password"
              autoComplete="current-password"
              className="h-14 rounded-2xl pl-11 text-base"
            />
          </div>
          {(error || accessMessage) && (
            <p role="alert" className="text-sm font-semibold text-destructive">{error ?? accessMessage}</p>
          )}
          <BigButton
            type="submit"
            disabled={isResolving || !email.trim() || !password}
            icon={isResolving ? <Loader2 className="size-5 animate-spin" /> : <ShieldCheck className="size-5" />}
          >
            {isResolving ? "Validando membresía" : "Identificar y entrar"}
          </BigButton>
        </form>

        <button
          type="button"
          onClick={() => setIsRecoveryOpen(true)}
          className="press mt-4 flex items-center gap-1.5 text-sm font-semibold text-primary"
        >
          <KeyRound className="size-4" />
          No puedo acceder
        </button>
      </main>

      <footer className="mx-auto w-full max-w-md text-center">
        <p className="text-[0.7rem] text-muted-foreground">
          DORI Operaciones · Acceso sujeto a permisos y auditoría
        </p>
      </footer>

      <Dialog open={isRecoveryOpen} onOpenChange={setIsRecoveryOpen}>
        <DialogContent className="max-w-sm rounded-3xl">
          <DialogHeader>
            <DialogTitle>Recuperar acceso</DialogTitle>
            <DialogDescription>
              La consola no crea contraseñas ni simula solicitudes. Pide al responsable autorizado de DORI que restablezca tu cuenta en Supabase Auth y confirme que conservas una membresía supervisora vigente en tu estación.
            </DialogDescription>
          </DialogHeader>
          <BigButton onClick={() => setIsRecoveryOpen(false)}>Entendido</BigButton>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default Login;
