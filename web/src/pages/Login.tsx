import { KeyRound, Loader2 } from "lucide-react";
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { toast } from "sonner";

import { BigButton } from "@/components/Pieces";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { useConsoleAuth } from "@/console/ConsoleAuth";

/**
 * The only access door for Consola DORI. Supabase Auth proves the credential and
 * console_identity then proves the active console/supervisor membership and station scope.
 * There is deliberately no local directory, biometric shortcut or simulated recovery.
 */
const Login = () => {
  const { accessMessage, isResolving, signInConsole } = useConsoleAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isRecoveryOpen, setIsRecoveryOpen] = useState(false);

  const submitCredentials = async (): Promise<void> => {
    setError(null);
    try {
      await signInConsole(email.trim(), password);
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
    <div className="dori-login-shell relative flex min-h-dvh flex-col items-center justify-center overflow-hidden px-5 py-8 text-foreground sm:px-8">
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_top,hsl(77_100%_62%_/_0.13),transparent_52%),radial-gradient(ellipse_at_bottom_right,hsl(190_100%_65%_/_0.06),transparent_58%),linear-gradient(145deg,hsl(210_22%_4%),hsl(207_22%_8%))]" />

      <main className="dori-login-content relative z-10 w-full max-w-[26rem] animate-rise-in">
        <header className="mb-8 text-center">
          <p className="text-[2.75rem] font-black leading-none tracking-[-0.055em] text-foreground">DORI</p>
          <p className="mt-2 text-[0.7rem] font-medium uppercase tracking-[0.25em] text-muted-foreground">La movilidad del futuro</p>
        </header>

        <section className="dori-login-card rounded-[2rem] border border-white/10 bg-white/[0.06] px-5 py-6 shadow-[0_24px_70px_-28px_hsl(0_0%_0%_/_0.95)] backdrop-blur-2xl sm:px-7 sm:py-8">
          <form
          className="space-y-3"
          onSubmit={(event) => {
            event.preventDefault();
            void submitCredentials();
          }}
        >
          <label className="sr-only" htmlFor="console-email">Correo</label>
          <Input
            id="console-email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            placeholder="Correo"
            type="email"
            autoComplete="email"
            autoCapitalize="none"
            spellCheck={false}
            className="h-14 rounded-2xl border-white/10 bg-black/20 px-4 text-base placeholder:text-muted-foreground/75 focus-visible:ring-primary/60"
          />
          <label className="sr-only" htmlFor="console-password">Contraseña</label>
          <Input
            id="console-password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            placeholder="Contraseña"
            type="password"
            autoComplete="current-password"
            className="h-14 rounded-2xl border-white/10 bg-black/20 px-4 text-base placeholder:text-muted-foreground/75 focus-visible:ring-primary/60"
          />
          {(error || accessMessage) && (
            <p role="alert" className="rounded-2xl border border-destructive/30 bg-destructive/10 px-4 py-3 text-sm font-semibold leading-snug text-destructive">{error ?? accessMessage}</p>
          )}
          <button
            type="submit"
            disabled={isResolving || !email.trim() || !password}
            className="dori-login-cta press flex h-14 w-full items-center justify-center gap-2 rounded-2xl bg-primary px-5 text-base font-bold tracking-tight text-primary-foreground shadow-[0_12px_30px_-14px_hsl(77_100%_62%_/_0.9)] transition-opacity disabled:pointer-events-none disabled:opacity-40"
          >
            {isResolving && <Loader2 className="size-5 animate-spin" />}
            {isResolving ? "Validando membresía" : "Iniciar sesión"}
          </button>
        </form>

        <button
          type="button"
          onClick={() => setIsRecoveryOpen(true)}
          className="dori-login-recovery press mt-5 flex w-full items-center justify-center gap-1.5 text-sm font-semibold text-muted-foreground transition-colors hover:text-primary"
        >
          <KeyRound className="size-4" />
          No puedo acceder
        </button>
          <footer className="mt-8 text-center text-[0.68rem] text-muted-foreground/80">
            Entorno de pruebas · Consola DORI
          </footer>
        </section>
      </main>

      <Dialog open={isRecoveryOpen} onOpenChange={setIsRecoveryOpen}>
        <DialogContent className="max-w-sm rounded-3xl">
          <DialogHeader>
            <DialogTitle>Recuperar acceso</DialogTitle>
            <DialogDescription>
              La consola no crea contraseñas ni simula solicitudes. Pide al responsable autorizado de DORI que restablezca tu cuenta en Supabase Auth y confirme que conservas una membresía autorizada vigente en tu estación.
            </DialogDescription>
          </DialogHeader>
          <BigButton onClick={() => setIsRecoveryOpen(false)}>Entendido</BigButton>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default Login;
