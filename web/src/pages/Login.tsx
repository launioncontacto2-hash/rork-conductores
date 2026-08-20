import {
  AtSign,
  IdCard,
  KeyRound,
  Loader2,
  LockKeyhole,
  ScanFace,
  ShieldCheck,
  Users,
  Zap,
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { toast } from "sonner";

import { BigButton } from "@/components/Pieces";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import {
  authenticateStaff,
  ROLE,
  scopeDescription,
  STAFF_ACCOUNTS,
  STATIONS,
  REGIONS,
  type SignInMethod,
  type StaffAccount,
} from "@/lib/org";
import { cn } from "@/lib/utils";
import { useFleet } from "@/store/fleet";

const MAX_BIOMETRIC_ATTEMPTS = 3;

type Mode = "biometric" | "credentials";
type CredentialMode = "email" | "employee";

const FaceIdBadge = ({ state, accent }: { state: "idle" | "scanning" | "failed"; accent: string }) => (
  <div className="relative grid size-40 place-items-center">
    <span
      className={cn(
        "absolute size-40 rounded-[2.4rem] border-2",
        state === "scanning" && "animate-volt-pulse",
      )}
      style={{ borderColor: state === "failed" ? "hsl(var(--destructive))" : `${accent}73` }}
    />
    <span
      className="absolute size-40 rounded-[2.4rem] blur-2xl"
      style={{ backgroundColor: state === "failed" ? "hsl(var(--destructive) / 0.2)" : `${accent}33` }}
    />
    <ScanFace
      className="relative size-20"
      strokeWidth={1.4}
      style={{ color: state === "failed" ? "hsl(var(--destructive))" : accent }}
    />
    {state === "scanning" && (
      <span className="absolute left-6 right-6 h-0.5 animate-scan-sweep bg-primary shadow-[0_0_16px_hsl(var(--primary))]" />
    )}
  </div>
);

/** Brief confirmation of the identified role before its interface is built. */
const RoleHandoff = ({ account }: { account: StaffAccount }) => {
  const role = ROLE[account.role];
  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-background/95 backdrop-blur-sm">
      <div className="animate-rise-in flex flex-col items-center gap-4 px-8 text-center">
        <span
          className="grid size-24 place-items-center rounded-full border-2"
          style={{ backgroundColor: `${role.accent}1f`, borderColor: `${role.accent}80`, color: role.accent }}
        >
          <ShieldCheck className="size-11" strokeWidth={1.6} />
        </span>
        <div className="space-y-1.5">
          <p className="label-caps">Rol identificado</p>
          <p className="text-2xl font-black tracking-tight" style={{ color: role.accent }}>
            {role.label}
          </p>
          <p className="text-sm font-semibold">{account.name}</p>
          <p className="text-xs text-muted-foreground">{scopeDescription(account)}</p>
        </div>
        <p className="text-xs text-muted-foreground">Abriendo {role.workspaceTitle.toLowerCase()}…</p>
      </div>
    </div>
  );
};

/**
 * Access to the network. Credentials are validated against the staff directory and the
 * resolved role is what opens an interface — a driver credential can never open the
 * supervisor, manager, maintenance or national workspace.
 *
 * Face ID unlocks only the credential enrolled on this device: the first access always
 * requires identifier + password, so biometrics can never escalate a role.
 */
const Login = () => {
  const { signIn, enrolledAccount } = useFleet();
  const navigate = useNavigate();

  const [mode, setMode] = useState<Mode>(() => (enrolledAccount ? "biometric" : "credentials"));
  const [attempts, setAttempts] = useState<number>(0);
  const [isScanning, setIsScanning] = useState<boolean>(false);
  const [lastFailed, setLastFailed] = useState<boolean>(false);
  const [handoff, setHandoff] = useState<StaffAccount | null>(null);

  const [credentialMode, setCredentialMode] = useState<CredentialMode>("email");
  const [identifier, setIdentifier] = useState<string>("");
  const [password, setPassword] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const [isRecoveryOpen, setIsRecoveryOpen] = useState<boolean>(false);
  const [isDirectoryOpen, setIsDirectoryOpen] = useState<boolean>(false);
  const [recoveryTarget, setRecoveryTarget] = useState<string>("");

  useEffect(() => {
    if (!enrolledAccount) setMode("credentials");
  }, [enrolledAccount]);

  /** Shows the identified role for a beat, then opens that role's interface only. */
  const grantAccess = useCallback(
    (account: StaffAccount, method: SignInMethod): void => {
      setHandoff(account);
      window.setTimeout(() => {
        signIn(account, method);
        navigate(ROLE[account.role].home, { replace: true });
      }, 1150);
    },
    [signIn, navigate],
  );

  const runFaceId = useCallback((): void => {
    if (!enrolledAccount) {
      setMode("credentials");
      return;
    }
    setIsScanning(true);
    setLastFailed(false);
    window.setTimeout(() => {
      setIsScanning(false);
      grantAccess(enrolledAccount, "biometric");
    }, 1200);
  }, [enrolledAccount, grantAccess]);

  const failFaceId = useCallback((): void => {
    const next = attempts + 1;
    setAttempts(next);
    setLastFailed(true);
    if (next >= MAX_BIOMETRIC_ATTEMPTS) {
      setMode("credentials");
      toast.error("Face ID no disponible", { description: "Ingresa con tus credenciales" });
      return;
    }
    toast.error("Rostro no reconocido", { description: `Intento ${next} de ${MAX_BIOMETRIC_ATTEMPTS}` });
  }, [attempts]);

  const submitCredentials = (): void => {
    const outcome = authenticateStaff(identifier, password);
    if (outcome.status !== "granted") {
      setError(outcome.message);
      toast.error("Acceso denegado", { description: outcome.message });
      return;
    }
    setError(null);
    setPassword("");
    grantAccess(outcome.account, "credentials");
  };

  const accent = enrolledAccount ? ROLE[enrolledAccount.role].accent : "#C8FF3C";

  return (
    <div className="station-bg flex min-h-dvh flex-col justify-between px-6 py-10">
      <div className="mx-auto w-full max-w-md">
        <div className="flex items-center gap-3">
          <span className="grid size-12 place-items-center rounded-2xl bg-primary/15 text-primary volt-glow">
            <Zap className="size-7" strokeWidth={2.6} />
          </span>
          <div>
            <p className="text-xl font-black leading-none tracking-tight">TURNO EV</p>
            <p className="label-caps mt-1">Acceso por rol y estación</p>
          </div>
        </div>
      </div>

      {mode === "biometric" && enrolledAccount ? (
        <div className="mx-auto w-full max-w-md animate-rise-in text-center">
          <div className="mx-auto">
            <FaceIdBadge
              state={isScanning ? "scanning" : lastFailed ? "failed" : "idle"}
              accent={accent}
            />
          </div>
          <h1 className="mt-8 text-2xl font-black tracking-tight">
            {isScanning ? "Verificando rostro…" : "Inicia con Face ID"}
          </h1>

          <div className="mt-4 flex flex-col items-center gap-2">
            <p className="text-sm font-bold">{enrolledAccount.name}</p>
            <span
              className="rounded-full border px-3 py-1 text-[0.6rem] font-black uppercase tracking-wider"
              style={{
                color: accent,
                borderColor: `${accent}66`,
                backgroundColor: `${accent}1f`,
              }}
            >
              {ROLE[enrolledAccount.role].label}
            </span>
            <p className="text-xs text-muted-foreground">{scopeDescription(enrolledAccount)}</p>
          </div>

          <p className={cn("mx-auto mt-4 max-w-xs text-sm", lastFailed ? "text-destructive" : "text-muted-foreground")}>
            {lastFailed
              ? `Intento ${attempts} de ${MAX_BIOMETRIC_ATTEMPTS}. Después de 3 intentos pedimos tus credenciales.`
              : "Face ID abre únicamente la credencial vinculada a este dispositivo."}
          </p>

          <div className="mt-7 space-y-3">
            <BigButton
              onClick={runFaceId}
              disabled={isScanning}
              icon={isScanning ? <Loader2 className="size-5 animate-spin" /> : <ScanFace className="size-5" />}
            >
              {isScanning ? "Escaneando" : "Usar Face ID"}
            </BigButton>
            <button
              type="button"
              onClick={failFaceId}
              disabled={isScanning}
              className="press h-12 w-full rounded-2xl border border-border/60 text-sm font-semibold text-muted-foreground disabled:opacity-40"
            >
              No reconoce mi rostro
            </button>
            <button
              type="button"
              onClick={() => {
                setMode("credentials");
                setAttempts(0);
                setLastFailed(false);
              }}
              className="press w-full text-sm font-semibold text-muted-foreground"
            >
              Entrar con otra credencial
            </button>
          </div>
        </div>
      ) : (
        <div className="mx-auto w-full max-w-md animate-rise-in">
          <h1 className="text-2xl font-black tracking-tight">Identifícate</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Detectamos tu rol y estación con tus credenciales, y abrimos solo tu interfaz.
          </p>

          <div className="mt-6 grid grid-cols-2 gap-2 rounded-2xl border border-border/70 bg-secondary/40 p-1.5">
            {(
              [
                { id: "email", label: "Correo", icon: AtSign },
                { id: "employee", label: "N° empleado", icon: IdCard },
              ] as { id: CredentialMode; label: string; icon: typeof AtSign }[]
            ).map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                type="button"
                onClick={() => {
                  setCredentialMode(id);
                  setIdentifier("");
                }}
                className={cn(
                  "press flex h-11 items-center justify-center gap-2 rounded-xl text-sm font-semibold",
                  credentialMode === id ? "bg-primary text-primary-foreground" : "text-muted-foreground",
                )}
              >
                <Icon className="size-4" />
                {label}
              </button>
            ))}
          </div>

          <form
            className="mt-4 space-y-3"
            onSubmit={(event) => {
              event.preventDefault();
              submitCredentials();
            }}
          >
            <Input
              value={identifier}
              onChange={(event) => setIdentifier(event.target.value)}
              placeholder={credentialMode === "email" ? "correo@turnoev.mx" : "EV-1042"}
              type={credentialMode === "email" ? "email" : "text"}
              autoComplete={credentialMode === "email" ? "email" : "username"}
              className="h-14 rounded-2xl text-base"
            />
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
            {error && <p className="text-sm font-semibold text-destructive">{error}</p>}
            <BigButton type="submit" icon={<ShieldCheck className="size-5" />}>
              Identificar y entrar
            </BigButton>
          </form>

          <div className="mt-4 flex items-center justify-between text-sm">
            <button
              type="button"
              onClick={() => setIsRecoveryOpen(true)}
              className="press flex items-center gap-1.5 font-semibold text-primary"
            >
              <KeyRound className="size-4" />
              Recuperar contraseña
            </button>
            {enrolledAccount && (
              <button
                type="button"
                onClick={() => {
                  setMode("biometric");
                  setAttempts(0);
                  setLastFailed(false);
                }}
                className="press font-semibold text-muted-foreground"
              >
                Volver a Face ID
              </button>
            )}
          </div>
        </div>
      )}

      <div className="mx-auto w-full max-w-md space-y-2 text-center">
        <button
          type="button"
          onClick={() => setIsDirectoryOpen(true)}
          className="press inline-flex items-center gap-2 text-xs font-semibold text-muted-foreground"
        >
          <Users className="size-4" />
          Cuentas de demostración
        </button>
        <p className="text-[0.7rem] text-muted-foreground">
          {STATIONS.length} estaciones · {REGIONS.length} regiones · v1.0 datos simulados
        </p>
      </div>

      <Dialog open={isRecoveryOpen} onOpenChange={setIsRecoveryOpen}>
        <DialogContent className="max-w-sm rounded-3xl">
          <DialogHeader>
            <DialogTitle>Recuperar contraseña</DialogTitle>
            <DialogDescription>
              Los conductores restablecen con el supervisor de su estación. Supervisores, gerencia y
              mantenimiento lo hacen con dirección nacional.
            </DialogDescription>
          </DialogHeader>
          <Input
            value={recoveryTarget}
            onChange={(event) => setRecoveryTarget(event.target.value)}
            placeholder="Correo o número de empleado"
            className="h-14 rounded-2xl"
          />
          <BigButton
            onClick={() => {
              setIsRecoveryOpen(false);
              setRecoveryTarget("");
              toast.success("Solicitud enviada", {
                description: "Quien generó tu registro validará el restablecimiento.",
              });
            }}
            disabled={recoveryTarget.trim().length < 4}
          >
            Enviar solicitud
          </BigButton>
        </DialogContent>
      </Dialog>

      <Dialog open={isDirectoryOpen} onOpenChange={setIsDirectoryOpen}>
        <DialogContent className="max-h-[85dvh] max-w-sm overflow-y-auto rounded-3xl">
          <DialogHeader>
            <DialogTitle>Cuentas de demostración</DialogTitle>
            <DialogDescription>
              Toca una cuenta para llenar sus datos y revisar la interfaz que abre cada rol.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            {STAFF_ACCOUNTS.map((account) => {
              const role = ROLE[account.role];
              return (
                <button
                  key={account.id}
                  type="button"
                  onClick={() => {
                    setCredentialMode("email");
                    setIdentifier(account.email);
                    setPassword(account.password);
                    setMode("credentials");
                    setError(null);
                    setIsDirectoryOpen(false);
                  }}
                  className="press panel-flat w-full space-y-1.5 p-3 text-left"
                >
                  <div className="flex items-center justify-between gap-2">
                    <span
                      className="rounded-full border px-2 py-0.5 text-[0.55rem] font-black uppercase tracking-wider"
                      style={{
                        color: role.accent,
                        borderColor: `${role.accent}66`,
                        backgroundColor: `${role.accent}1f`,
                      }}
                    >
                      {role.label}
                    </span>
                    <span className="text-[0.65rem] font-semibold text-muted-foreground">
                      {account.employeeNumber}
                    </span>
                  </div>
                  <p className="text-sm font-bold">{account.name}</p>
                  <p className="text-[0.7rem] text-muted-foreground">{scopeDescription(account)}</p>
                  <p className="text-[0.65rem] text-muted-foreground">
                    {account.email} · {account.password}
                  </p>
                </button>
              );
            })}
          </div>
        </DialogContent>
      </Dialog>

      {handoff && <RoleHandoff account={handoff} />}
    </div>
  );
};

export default Login;
