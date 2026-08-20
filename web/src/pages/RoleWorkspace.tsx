import { BadgeCheck, Hammer, LogOut, ShieldAlert, Smartphone, Zap } from "lucide-react";

import { DemoClock } from "@/components/DemoClock";
import { SLOT_LABEL, SLOT_RANGE_LABEL } from "@/lib/schedule";
import {
  accountById,
  accountInitials,
  ROLE,
  scopeDescription,
  stationById,
  type StaffAccount,
} from "@/lib/org";
import { useFleet } from "@/store/fleet";

const Row = ({ label, value }: { label: string; value: string }) => (
  <div className="flex items-start justify-between gap-4 text-sm">
    <span className="text-muted-foreground">{label}</span>
    <span className="text-right font-semibold">{value}</span>
  </div>
);

const RoleChip = ({ account, compact = false }: { account: StaffAccount; compact?: boolean }) => {
  const role = ROLE[account.role];
  return (
    <span
      className={compact ? "inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[0.6rem] font-black uppercase tracking-wider" : "inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-[0.65rem] font-black uppercase tracking-wider"}
      style={{
        color: role.accent,
        borderColor: `${role.accent}66`,
        backgroundColor: `${role.accent}1f`,
      }}
    >
      {role.label}
    </span>
  );
};

/** Interface reserved for a role whose modules are not published yet. It renders only
 *  the scope the credential is entitled to, never driver data. */
const RoleWorkspace = () => {
  const { account, session, signOut, forgetDevice } = useFleet();

  if (!account) return null;

  const role = ROLE[account.role];
  const station = stationById(account.stationId);
  const creator = accountById(account.createdById);
  const authorizer = accountById(account.authorizedById);

  return (
    <div className="station-bg min-h-dvh">
      <div className="mx-auto w-full max-w-2xl space-y-4 px-5 pb-16 pt-8">
        <header className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-3">
            <span
              className="grid size-12 place-items-center rounded-2xl"
              style={{ backgroundColor: `${role.accent}1f`, color: role.accent }}
            >
              <Zap className="size-6" strokeWidth={2.6} />
            </span>
            <div>
              <p className="text-xl font-black leading-none tracking-tight">{role.workspaceTitle}</p>
              <p className="label-caps mt-1">Turno EV · red nacional</p>
            </div>
          </div>
          <DemoClock />
        </header>

        <RoleChip account={account} />

        <section className="panel space-y-4 p-5">
          <div className="flex items-center gap-3">
            <span
              className="grid size-14 place-items-center rounded-full border-2 text-lg font-black"
              style={{ color: role.accent, borderColor: `${role.accent}80` }}
            >
              {accountInitials(account)}
            </span>
            <div>
              <p className="font-bold">{account.name}</p>
              <p className="text-xs text-muted-foreground">
                {account.employeeNumber} · {account.status === "active" ? "Activo" : "Suspendido"}
              </p>
            </div>
          </div>

          <div className="h-px bg-border/70" />

          <div className="space-y-2.5">
            <Row label="Alcance" value={role.scopeLabel} />
            <Row label="Asignación" value={scopeDescription(account)} />
            {account.slot && (
              <Row label="Cobertura" value={`${SLOT_LABEL[account.slot]} · ${SLOT_RANGE_LABEL[account.slot]}`} />
            )}
            {station && <Row label="Código de estación" value={station.code} />}
            {station && <Row label="Capacidad" value={`${station.vehicleCapacity} unidades · 4 turnos`} />}
            {session && <Row label="Acceso" value={session.method === "biometric" ? "Face ID" : "Credenciales"} />}
          </div>
        </section>

        <section className="panel space-y-3 p-5">
          <p className="label-caps">Permisos de esta credencial</p>
          <ul className="space-y-2.5">
            {role.capabilities.map((capability) => (
              <li key={capability} className="flex gap-2.5 text-sm">
                <BadgeCheck className="mt-0.5 size-4 shrink-0" style={{ color: role.accent }} />
                {capability}
              </li>
            ))}
          </ul>
        </section>

        <section className="panel space-y-3 p-5">
          <p className="label-caps">Jerarquía de registros</p>
          <p className="text-sm">{role.registrationNote}</p>
          {role.canRegister.length > 0 && (
            <div className="flex flex-wrap gap-2">
              {role.canRegister.map((target) => (
                <span
                  key={target}
                  className="rounded-full border px-2.5 py-1 text-[0.6rem] font-black uppercase tracking-wider"
                  style={{
                    color: ROLE[target].accent,
                    borderColor: `${ROLE[target].accent}66`,
                    backgroundColor: `${ROLE[target].accent}1f`,
                  }}
                >
                  {ROLE[target].label}
                </span>
              ))}
            </div>
          )}
          <div className="space-y-2.5 pt-1">
            {creator && <Row label="Registrado por" value={`${creator.name} · ${ROLE[creator.role].shortLabel}`} />}
            {authorizer && (
              <Row label="Autorizado por" value={`${authorizer.name} · ${ROLE[authorizer.role].shortLabel}`} />
            )}
          </div>
        </section>

        <section className="panel space-y-3 p-5">
          <div className="flex gap-3 rounded-2xl border border-info/40 bg-info/10 p-4">
            <Hammer className="mt-0.5 size-5 shrink-0 text-info" />
            <div>
              <p className="text-sm font-bold">Interfaz en construcción</p>
              <p className="mt-1 text-xs text-muted-foreground">
                Tu sesión ya está identificada y protegida. Los módulos de {role.shortLabel.toLowerCase()} se
                publican en la siguiente entrega.
              </p>
            </div>
          </div>
          <p className="flex gap-2 text-xs text-muted-foreground">
            <ShieldAlert className="size-4 shrink-0" />
            Ningún dato de otra interfaz se carga en esta sesión: la app solo resuelve las pantallas del rol
            autenticado.
          </p>
        </section>

        <div className="space-y-3 pt-2">
          <button
            type="button"
            onClick={signOut}
            className="press flex h-14 w-full items-center justify-center gap-2 rounded-2xl border border-border/70 bg-secondary/40 font-bold"
          >
            <LogOut className="size-5" />
            Cerrar sesión
          </button>
          <button
            type="button"
            onClick={forgetDevice}
            className="press flex w-full items-center justify-center gap-2 text-xs font-semibold text-muted-foreground"
          >
            <Smartphone className="size-4" />
            Desvincular este dispositivo
          </button>
        </div>
      </div>
    </div>
  );
};

export default RoleWorkspace;
