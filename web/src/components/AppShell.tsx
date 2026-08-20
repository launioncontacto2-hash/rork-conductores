import { Award, CalendarClock, ClipboardList, CreditCard, Gauge, Target, Zap } from "lucide-react";
import { type ReactNode } from "react";
import { NavLink, useLocation } from "react-router-dom";

import { DemoClock } from "@/components/DemoClock";
import { clock, dateLong, mxn } from "@/lib/format";
import { GROUP_LABEL, SLOT_LABEL, SLOT_RANGE_LABEL } from "@/lib/schedule";
import { goalProgress, weeklyLateDebt } from "@/lib/selectors";
import { cn } from "@/lib/utils";
import { useFleet } from "@/store/fleet";

interface TabDefinition {
  to: string;
  label: string;
  icon: typeof Gauge;
}

const TABS: TabDefinition[] = [
  { to: "/turno", label: "Turno", icon: Gauge },
  { to: "/metas", label: "Metas", icon: Target },
  { to: "/bonos", label: "Bonos", icon: Award },
  { to: "/credito", label: "Créditos", icon: CreditCard },
  { to: "/historial", label: "Historial", icon: ClipboardList },
];

const TabBar = () => {
  const location = useLocation();

  return (
    <nav className="safe-b sticky bottom-0 z-30 border-t border-border/70 bg-background/85 px-2 pt-2 backdrop-blur-xl">
      <ul className="grid grid-cols-5 gap-1">
        {TABS.map(({ to, label, icon: Icon }) => {
          const isActive = location.pathname.startsWith(to);
          return (
            <li key={to}>
              <NavLink
                to={to}
                className={cn(
                  "press relative flex h-16 flex-col items-center justify-center gap-1 rounded-2xl text-[0.65rem] font-semibold tracking-tight",
                  isActive ? "bg-primary/12 text-primary" : "text-muted-foreground hover:text-foreground",
                )}
              >
                <span className="relative">
                  <Icon className="size-5" strokeWidth={isActive ? 2.4 : 1.8} />
                </span>
                {label}
                {isActive && <span className="absolute bottom-1 h-1 w-6 rounded-full bg-primary" />}
              </NavLink>
            </li>
          );
        })}
      </ul>
    </nav>
  );
};

const StationPanel = () => {
  const { driver, now, history, incomes, activeShift, credit, bonusPayableMxn } = useFleet();
  const progress = goalProgress(driver.shift.group, incomes, history, activeShift, now);
  const lateDebt = weeklyLateDebt(history, now);

  return (
    <aside className="hidden w-full max-w-sm flex-col justify-between p-10 lg:flex">
      <div>
        <div className="flex items-center gap-3">
          <span className="grid size-11 place-items-center rounded-2xl bg-primary/15 text-primary volt-glow">
            <Zap className="size-6" strokeWidth={2.6} />
          </span>
          <div>
            <p className="text-lg font-black leading-none tracking-tight">TURNO EV</p>
            <p className="label-caps mt-1">Operación de flotilla</p>
          </div>
        </div>

        <div className="mt-10 space-y-1">
          <p className="tabular text-6xl font-black leading-none tracking-tighter">{clock(now)}</p>
          <p className="text-sm capitalize text-muted-foreground">{dateLong(now)}</p>
        </div>

        <div className="mt-8 space-y-3 text-sm">
          <div className="panel-flat flex items-center justify-between px-4 py-3">
            <span className="label-caps">Turno</span>
            <span className="font-semibold">
              {SLOT_LABEL[driver.shift.slot]} · {SLOT_RANGE_LABEL[driver.shift.slot]}
            </span>
          </div>
          <div className="panel-flat flex items-center justify-between px-4 py-3">
            <span className="label-caps">Grupo</span>
            <span className="font-semibold">{GROUP_LABEL[driver.shift.group]}</span>
          </div>
          <div className="panel-flat flex items-center justify-between px-4 py-3">
            <span className="label-caps">Semana</span>
            <span className="tabular font-semibold text-primary">
              {mxn(progress.earnedWeek)} / {mxn(progress.weeklyGoal)}
            </span>
          </div>
          <div className="panel-flat flex items-center justify-between px-4 py-3">
            <span className="label-caps">Atraso</span>
            <span className={cn("tabular font-semibold", lateDebt > 0 ? "text-warning" : "text-primary")}>
              {lateDebt} min
            </span>
          </div>
          <div className="panel-flat flex items-center justify-between px-4 py-3">
            <span className="label-caps">Bonos</span>
            <span className="tabular font-semibold text-primary">{mxn(bonusPayableMxn)}</span>
          </div>
          <div className="panel-flat flex items-center justify-between px-4 py-3">
            <span className="label-caps">Crédito</span>
            <span className="tabular font-semibold">
              {credit ? mxn(credit.totalMxn - credit.paidMxn) : "Sin contrato"}
            </span>
          </div>
        </div>
      </div>

      <div className="space-y-4">
        <DemoClock />
        <p className="flex items-center gap-2 text-xs text-muted-foreground">
          <CalendarClock className="size-4" />
          Datos simulados · listo para Uber, GPS, OCR y telemetría
        </p>
      </div>
    </aside>
  );
};

/** Phone-shaped operational column, with a station dashboard beside it on desktop. */
export const AppShell = ({ children }: { children: ReactNode }) => (
  <div className="station-bg min-h-dvh">
    <div className="mx-auto flex w-full max-w-6xl justify-center">
      <StationPanel />
      <main className="flex h-dvh w-full max-w-md flex-col overflow-y-auto border-x border-border/50 bg-background/40 no-scrollbar">
        <div className="flex-1 pb-6">{children}</div>
        <TabBar />
      </main>
    </div>
  </div>
);
