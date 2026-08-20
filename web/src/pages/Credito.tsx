import {
  BadgeCheck,
  CalendarClock,
  CarFront,
  CreditCard,
  FileText,
  Gauge,
  HandCoins,
  Pause,
  Play,
  Signature,
  Sparkles,
  TrendingUp,
  Zap,
} from "lucide-react";
import { type ReactNode, useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";

import { BigButton, ProgressTrack, RingGauge, StatTile } from "@/components/Pieces";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import {
  CREDIT_BENEFITS,
  CREDIT_CAPTIONS,
  CREDIT_PROGRAM,
  CREDIT_RISK_DETAIL,
  CREDIT_RISK_LABEL,
  CREDIT_SCRIPT,
  CREDIT_STEPS,
  type CreditMetrics,
} from "@/lib/credit";
import { dateShort, km, mxn, stopwatch } from "@/lib/format";
import type { CreditAccount, CreditStatus } from "@/lib/types";
import { cn } from "@/lib/utils";
import { useFleet } from "@/store/fleet";

const BENEFIT_ICON: Record<string, ReactNode> = {
  down: <HandCoins className="size-4" />,
  approval: <Zap className="size-4" />,
  charger: <BadgeCheck className="size-4" />,
  km: <Gauge className="size-4" />,
  year: <Sparkles className="size-4" />,
  term: <CalendarClock className="size-4" />,
};

const STATUS_LABEL: Record<CreditStatus, string> = {
  paid: "Pagado",
  due: "Por pagar",
  late: "Vencido",
};

const statusClass = (status: CreditStatus): string =>
  status === "paid" ? "text-primary" : status === "due" ? "text-warning" : "text-destructive";

/** Explainer modal: looping fleet clip, narration and synced captions. */
const HowItWorksDialog = ({ open, onOpenChange }: { open: boolean; onOpenChange: (value: boolean) => void }) => {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [isPlaying, setIsPlaying] = useState<boolean>(false);
  const [elapsed, setElapsed] = useState<number>(0);
  const [duration, setDuration] = useState<number>(0);

  useEffect(() => {
    if (open) return;
    const audio = audioRef.current;
    if (audio) {
      audio.pause();
      audio.currentTime = 0;
    }
    setIsPlaying(false);
    setElapsed(0);
  }, [open]);

  const caption = useMemo(() => {
    const active = [...CREDIT_CAPTIONS].reverse().find((item) => elapsed >= item.start);
    return active?.text ?? CREDIT_CAPTIONS[0]?.text ?? "";
  }, [elapsed]);

  const toggle = (): void => {
    const audio = audioRef.current;
    if (!audio) return;
    if (audio.paused) {
      if (audio.ended) audio.currentTime = 0;
      void audio.play().catch(() => setIsPlaying(false));
      setIsPlaying(true);
    } else {
      audio.pause();
      setIsPlaying(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md overflow-hidden border-border/70 bg-background p-0">
        <div className="relative">
          <video
            src={CREDIT_PROGRAM.videoUrl}
            className="h-48 w-full object-cover"
            autoPlay
            muted
            loop
            playsInline
          />
          <div className="absolute inset-0 bg-gradient-to-t from-background via-background/40 to-transparent" />
        </div>

        <div className="space-y-4 px-5 pb-6">
          <DialogHeader className="space-y-1 text-left">
            <p className="label-caps">Cómo funciona</p>
            <DialogTitle className="text-lg font-black leading-tight">
              Bajamos el costo del riesgo, no lo cargamos al precio
            </DialogTitle>
          </DialogHeader>

          <p className="min-h-[72px] text-sm font-semibold leading-snug text-foreground/90 transition-opacity">
            {caption}
          </p>

          <div>
            <ProgressTrack value={elapsed} goal={Math.max(duration, 1)} />
            <div className="mt-1.5 flex items-center justify-between text-[0.65rem] font-semibold tabular-nums text-muted-foreground">
              <span>{stopwatch(Math.floor(elapsed))}</span>
              <span>{stopwatch(Math.floor(duration))}</span>
            </div>
          </div>

          <BigButton
            icon={isPlaying ? <Pause className="size-5" /> : <Play className="size-5" />}
            onClick={toggle}
          >
            {isPlaying ? "Pausar explicación" : elapsed > 0 ? "Continuar" : "Reproducir explicación"}
          </BigButton>

          <p className="text-[0.7rem] leading-relaxed text-muted-foreground">{CREDIT_SCRIPT}</p>
        </div>

        <audio
          ref={audioRef}
          src={CREDIT_PROGRAM.narrationUrl}
          onLoadedMetadata={(event) => setDuration(event.currentTarget.duration)}
          onTimeUpdate={(event) => setElapsed(event.currentTarget.currentTime)}
          onEnded={() => setIsPlaying(false)}
        />
      </DialogContent>
    </Dialog>
  );
};

/** Promotional banner shown while the driver has no contract. */
const CreditOffer = ({ onHowItWorks, onRequest }: { onHowItWorks: () => void; onRequest: () => void }) => (
  <div className="space-y-4">
    <section className="panel overflow-hidden volt-glow">
      <div className="relative">
        <img
          src={CREDIT_PROGRAM.imageUrl}
          alt={CREDIT_PROGRAM.vehicleModel}
          className="h-52 w-full object-cover"
        />
        <span className="absolute left-4 top-4 rounded-full bg-primary px-2.5 py-1 text-[0.6rem] font-black uppercase tracking-wider text-primary-foreground">
          Seminueva certificada
        </span>
        <div className="absolute inset-x-0 bottom-0 h-24 bg-gradient-to-t from-card to-transparent" />
      </div>
      <div className="space-y-2 p-5">
        <p className="label-caps">Venta de unidades de flotilla</p>
        <h2 className="text-2xl font-black leading-tight tracking-tight">
          Llévate tu {CREDIT_PROGRAM.vehicleModel} a crédito
        </h2>
        <p className="text-sm text-muted-foreground">
          Sin enganche, con aprobación inmediata y equipo de carga incluido. Kilometraje no mayor a{" "}
          {km(CREDIT_PROGRAM.maxHandoverKm)}.
        </p>
      </div>
    </section>

    <div className="grid grid-cols-2 gap-3">
      {CREDIT_BENEFITS.map((benefit) => (
        <article key={benefit.id} className="panel-flat flex min-h-[116px] flex-col gap-1.5 p-4">
          <span className="text-primary">{BENEFIT_ICON[benefit.id]}</span>
          <p className="text-sm font-bold leading-tight">{benefit.title}</p>
          <p className="text-[0.7rem] leading-snug text-muted-foreground">{benefit.detail}</p>
        </article>
      ))}
    </div>

    <section className="panel p-5">
      <p className="label-caps">Así funciona en 4 pasos</p>
      <ul className="mt-3 space-y-2.5">
        {CREDIT_STEPS.map((step) => (
          <li key={step.index} className="flex items-start gap-3">
            <span className="mt-0.5 grid size-6 shrink-0 place-items-center rounded-full bg-primary text-[0.7rem] font-black text-primary-foreground">
              {step.index}
            </span>
            <div>
              <p className="text-sm font-bold leading-tight">{step.title}</p>
              <p className="text-[0.7rem] leading-snug text-muted-foreground">{step.detail}</p>
            </div>
          </li>
        ))}
      </ul>
    </section>

    <div className="space-y-2.5">
      <BigButton icon={<Signature className="size-5" />} onClick={onRequest}>
        Solicitar mi crédito
      </BigButton>
      <BigButton icon={<Play className="size-5" />} tone="outline" onClick={onHowItWorks}>
        Cómo funciona
      </BigButton>
    </div>

    <p className="px-2 text-center text-[0.7rem] leading-relaxed text-muted-foreground">
      Descuento vía nómina · {CREDIT_PROGRAM.termWeeks} pagos semanales · plazo de {CREDIT_PROGRAM.termMonths} meses ·
      la unidad se entrega en el mes {CREDIT_PROGRAM.deliveryMonth}.
    </p>
  </div>
);

/** Full transparency dashboard for a signed contract. */
const ActiveCredit = ({ credit, metrics }: { credit: CreditAccount; metrics: CreditMetrics }) => {
  const [showTerms, setShowTerms] = useState<boolean>(false);
  const riskClass =
    metrics.risk === "low"
      ? "bg-primary/12 text-primary"
      : metrics.risk === "medium"
        ? "bg-warning/12 text-warning"
        : "bg-destructive/12 text-destructive";

  return (
    <div className="space-y-4">
      <section className="panel p-5">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="label-caps">Saldo del crédito</p>
            <p className="tabular mt-1 text-4xl font-black leading-none tracking-tighter">
              {mxn(metrics.balanceMxn)}
            </p>
            <p className="mt-1.5 truncate text-[0.7rem] text-muted-foreground">
              {credit.vehicleTarget} · contrato {credit.contractId}
            </p>
          </div>
          <div className="panel-flat shrink-0 px-3 py-2 text-center">
            <p className="tabular text-lg font-black leading-none">{metrics.weeksPaid}</p>
            <p className="text-[0.6rem] font-bold text-muted-foreground">de {CREDIT_PROGRAM.termWeeks}</p>
            <p className="label-caps mt-0.5">Semanas</p>
          </div>
        </div>

        <div className="mt-4">
          <ProgressTrack value={metrics.paidMxn} goal={credit.totalMxn} />
        </div>

        <div className="mt-3 grid grid-cols-3 gap-3">
          <StatTile label="Pagado" value={mxn(metrics.paidMxn)} tone="primary" />
          <StatTile label="Semanal" value={mxn(credit.weeklyMxn)} hint="Vía nómina" />
          <StatTile label="Restan" value={`${metrics.weeksRemaining}`} hint="Semanas" />
        </div>
      </section>

      <section className="panel p-5">
        <p className="label-caps flex items-center gap-1.5">
          <CalendarClock className="size-3.5" /> Próximo descuento
        </p>
        {metrics.nextPayment ? (
          <div className="mt-2 flex items-start justify-between">
            <div>
              <p className="text-base font-black leading-tight">{metrics.nextPayment.concept}</p>
              <p className="text-xs capitalize text-muted-foreground">
                {dateShort(new Date(metrics.nextPayment.dueDate))}
              </p>
            </div>
            <div className="text-right">
              <p className="tabular text-base font-black">{mxn(metrics.nextPayment.amountMxn)}</p>
              <p
                className={cn(
                  "text-[0.6rem] font-bold uppercase tracking-wider",
                  statusClass(metrics.nextPayment.status),
                )}
              >
                {STATUS_LABEL[metrics.nextPayment.status]}
              </p>
            </div>
          </div>
        ) : (
          <p className="mt-2 text-sm text-muted-foreground">No tienes abonos pendientes esta semana.</p>
        )}
        <p className="mt-3 text-[0.7rem] leading-relaxed text-muted-foreground">
          El descuento se aplica automáticamente en tu nómina semanal; no necesitas hacer transferencias.
        </p>
      </section>

      <section className="panel p-5">
        <p className="label-caps flex items-center gap-1.5">
          <CarFront className="size-3.5" /> Entrega de la unidad
        </p>
        <div className="mt-2 flex items-center gap-4">
          <div className="scale-[0.82]">
            <RingGauge
              value={metrics.monthsElapsed}
              goal={CREDIT_PROGRAM.deliveryMonth}
              headline={`${metrics.monthsElapsed}/${CREDIT_PROGRAM.deliveryMonth}`}
              caption="Meses"
            />
          </div>
          <div className="min-w-0 space-y-1.5">
            <p className={cn("text-sm font-black", metrics.isUnitDelivered && "text-primary")}>
              {metrics.isUnitDelivered ? "Unidad lista para entrega" : `Faltan ${metrics.monthsToDelivery} meses`}
            </p>
            <p className="text-[0.7rem] capitalize text-muted-foreground">
              Fecha estimada: {dateShort(metrics.estimatedDeliveryDate)}
            </p>
            <p className="text-[0.7rem] text-muted-foreground">
              Odómetro actual: {km(credit.assignedVehicleOdometerKm)}
            </p>
            <p className="text-[0.7rem] leading-snug text-muted-foreground">
              Sale de flotilla entre {km(CREDIT_PROGRAM.minHandoverKm)} y {km(CREDIT_PROGRAM.maxHandoverKm)}.
            </p>
          </div>
        </div>
        <div className="mt-4 rounded-2xl border border-info/40 bg-info/10 p-4">
          <p className="text-sm font-bold leading-snug">
            Mientras construyes tu historial, la unidad sigue operando en la flotilla.
          </p>
          <p className="mt-1 text-[0.7rem] leading-snug text-muted-foreground">
            Ese modelo es lo que nos permite venderte más barato que un crédito tradicional.
          </p>
        </div>
      </section>

      <section className="panel p-5">
        <div className="flex items-center justify-between">
          <p className="label-caps flex items-center gap-1.5">
            <TrendingUp className="size-3.5" /> Comportamiento crediticio
          </p>
          <span className={cn("rounded-full px-2.5 py-1 text-[0.6rem] font-black uppercase tracking-wider", riskClass)}>
            Riesgo {CREDIT_RISK_LABEL[metrics.risk]}
          </span>
        </div>
        <div className="mt-3 grid grid-cols-3 gap-3">
          <StatTile
            label="Cumplimiento"
            value={`${Math.round(metrics.complianceRate * 100)}%`}
            tone={metrics.complianceRate >= 0.95 ? "primary" : "warning"}
          />
          <StatTile label="Puntuales" value={`${credit.onTimePayments}`} tone="info" />
          <StatTile
            label="Atrasados"
            value={`${credit.latePayments}`}
            tone={credit.latePayments === 0 ? "default" : "danger"}
          />
        </div>
        <p className="mt-3 text-[0.7rem] leading-snug text-muted-foreground">{CREDIT_RISK_DETAIL[metrics.risk]}</p>
      </section>

      <section className="space-y-2.5">
        <p className="label-caps flex items-center gap-1.5 px-1">
          <CreditCard className="size-3.5" /> Historial de abonos
        </p>
        {credit.payments.map((payment) => (
          <article key={payment.id} className="panel-flat flex items-center justify-between p-4">
            <div>
              <p className="text-sm font-bold">{payment.concept}</p>
              <p className="text-xs capitalize text-muted-foreground">{dateShort(new Date(payment.dueDate))}</p>
            </div>
            <div className="text-right">
              <p className="tabular text-sm font-black">{mxn(payment.amountMxn)}</p>
              <p className={cn("text-[0.6rem] font-bold uppercase tracking-wider", statusClass(payment.status))}>
                {STATUS_LABEL[payment.status]}
              </p>
            </div>
          </article>
        ))}
      </section>

      <section className="panel p-5">
        <button
          type="button"
          onClick={() => setShowTerms((prev) => !prev)}
          className="press flex w-full items-center justify-between"
        >
          <span className="flex items-center gap-1.5 text-sm font-bold">
            <FileText className="size-4" /> Condiciones del contrato
          </span>
          <span className="text-xs text-muted-foreground">{showTerms ? "Ocultar" : "Ver"}</span>
        </button>
        {showTerms && (
          <dl className="mt-3 space-y-2">
            {[
              ["Firma", dateShort(new Date(credit.startedAt))],
              ["Enganche", "Sin enganche"],
              ["Monto financiado", mxn(credit.totalMxn)],
              ["Plazo", `${CREDIT_PROGRAM.termMonths} meses · ${CREDIT_PROGRAM.termWeeks} semanas`],
              ["Forma de pago", "Descuento semanal vía nómina"],
              ["Entrega de unidad", `Mes ${CREDIT_PROGRAM.deliveryMonth}`],
              ["Último abono", dateShort(metrics.contractEndDate)],
            ].map(([label, value]) => (
              <div key={label} className="panel-flat flex items-center justify-between px-3 py-2.5">
                <dt className="text-xs text-muted-foreground">{label}</dt>
                <dd className="text-right text-xs font-bold capitalize">{value}</dd>
              </div>
            ))}
          </dl>
        )}
      </section>
    </div>
  );
};

const Credito = () => {
  const { credit, creditMetrics, requestCredit, loadCreditDemoProgress, cancelCredit } = useFleet();
  const [howItWorks, setHowItWorks] = useState<boolean>(false);

  const sign = (): void => {
    requestCredit();
    toast.success("¡Crédito aprobado!", {
      description: `Firmaste tu contrato del ${CREDIT_PROGRAM.vehicleModel} sin enganche. El descuento semanal empieza en 7 días.`,
    });
  };

  return (
    <div className="space-y-4 px-4 pb-4 pt-5">
      <header>
        <p className="label-caps">Créditos</p>
        <h1 className="text-xl font-black tracking-tight">Tu unidad a crédito</h1>
      </header>

      {credit && creditMetrics ? (
        <ActiveCredit credit={credit} metrics={creditMetrics} />
      ) : (
        <CreditOffer onHowItWorks={() => setHowItWorks(true)} onRequest={sign} />
      )}

      <section className="panel-flat space-y-2 p-4 text-center">
        <p className="label-caps">Vista de demostración</p>
        <div className="flex flex-wrap justify-center gap-3 text-xs font-bold text-info">
          <button type="button" className="press underline" onClick={loadCreditDemoProgress}>
            Contrato semana 14
          </button>
          {credit && (
            <button type="button" className="press underline" onClick={cancelCredit}>
              Ver anuncio
            </button>
          )}
        </div>
      </section>

      <HowItWorksDialog open={howItWorks} onOpenChange={setHowItWorks} />
    </div>
  );
};

export default Credito;
