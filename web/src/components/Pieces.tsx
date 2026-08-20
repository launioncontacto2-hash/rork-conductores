import { BatteryFull, BatteryLow, BatteryMedium, Check, Camera, ChevronLeft } from "lucide-react";
import { useId, useRef, type ReactNode } from "react";
import { useNavigate } from "react-router-dom";

import { compressImage } from "@/lib/storage";
import { cn } from "@/lib/utils";

/** Screen header with a large back target — usable with one thumb while parked. */
export const ScreenHeader = ({
  title,
  subtitle,
  right,
  onBack,
}: {
  title: string;
  subtitle?: string;
  right?: ReactNode;
  onBack?: () => void;
}) => {
  const navigate = useNavigate();
  return (
    <header className="sticky top-0 z-20 flex items-center gap-3 border-b border-border/60 bg-background/85 px-4 py-3 backdrop-blur-xl">
      <button
        type="button"
        onClick={() => (onBack ? onBack() : navigate(-1))}
        className="press grid size-11 shrink-0 place-items-center rounded-2xl border border-border/70 bg-secondary/50"
        aria-label="Regresar"
      >
        <ChevronLeft className="size-6" />
      </button>
      <div className="min-w-0 flex-1">
        <h1 className="truncate text-lg font-bold leading-tight">{title}</h1>
        {subtitle && <p className="truncate text-xs text-muted-foreground">{subtitle}</p>}
      </div>
      {right}
    </header>
  );
};

export const StatTile = ({
  label,
  value,
  hint,
  tone = "default",
  icon,
}: {
  label: string;
  value: string;
  hint?: string;
  tone?: "default" | "primary" | "warning" | "danger" | "info";
  icon?: ReactNode;
}) => {
  const toneClass = {
    default: "text-foreground",
    primary: "text-primary",
    warning: "text-warning",
    danger: "text-destructive",
    info: "text-info",
  }[tone];

  return (
    <div className="panel-flat p-4">
      <div className="flex items-center justify-between">
        <p className="label-caps">{label}</p>
        {icon}
      </div>
      <p className={cn("tabular mt-2 text-2xl font-black leading-none tracking-tight", toneClass)}>{value}</p>
      {hint && <p className="mt-1.5 text-[0.7rem] leading-tight text-muted-foreground">{hint}</p>}
    </div>
  );
};

export const BatteryPill = ({ level, className }: { level: number; className?: string }) => {
  const tone = level > 70 ? "text-primary" : level > 40 ? "text-warning" : "text-destructive";
  const Icon = level > 70 ? BatteryFull : level > 40 ? BatteryMedium : BatteryLow;
  return (
    <span
      className={cn(
        "tabular inline-flex items-center gap-1.5 rounded-full border border-border/70 bg-secondary/50 px-2.5 py-1 text-sm font-bold",
        tone,
        className,
      )}
    >
      <Icon className="size-4" />
      {Math.round(level)}%
    </span>
  );
};

export const ProgressTrack = ({
  value,
  goal,
  tone = "primary",
  marker,
}: {
  value: number;
  goal: number;
  tone?: "primary" | "warning" | "info";
  marker?: number;
}) => {
  const pct = goal > 0 ? Math.min(100, (value / goal) * 100) : 0;
  const markerPct = marker !== undefined && goal > 0 ? Math.min(100, (marker / goal) * 100) : null;
  const barTone = {
    primary: "bg-primary",
    warning: "bg-warning",
    info: "bg-info",
  }[tone];

  return (
    <div className="relative h-3 w-full overflow-hidden rounded-full bg-secondary/70">
      <div
        className={cn("h-full rounded-full transition-[width] duration-700 ease-out", barTone)}
        style={{ width: `${pct}%` }}
      />
      {markerPct !== null && (
        <span
          className="absolute top-0 h-full w-0.5 bg-foreground/70"
          style={{ left: `${markerPct}%` }}
          aria-hidden
        />
      )}
    </div>
  );
};

/** Circular gauge used for the daily money goal. */
export const RingGauge = ({
  value,
  goal,
  caption,
  headline,
}: {
  value: number;
  goal: number;
  caption: string;
  headline: string;
}) => {
  const pct = goal > 0 ? Math.min(1, value / goal) : 0;
  const radius = 66;
  const circumference = 2 * Math.PI * radius;

  return (
    <div className="relative grid size-[168px] place-items-center">
      <svg viewBox="0 0 160 160" className="absolute size-full -rotate-90">
        <circle cx="80" cy="80" r={radius} fill="none" stroke="hsl(var(--secondary))" strokeWidth="12" />
        <circle
          cx="80"
          cy="80"
          r={radius}
          fill="none"
          stroke="hsl(var(--primary))"
          strokeWidth="12"
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={circumference * (1 - pct)}
          className="transition-[stroke-dashoffset] duration-1000 ease-out"
          style={{ filter: "drop-shadow(0 0 10px hsl(var(--primary) / 0.5))" }}
        />
      </svg>
      <div className="text-center">
        <p className="tabular text-3xl font-black leading-none tracking-tight">{headline}</p>
        <p className="mt-1 text-[0.68rem] uppercase tracking-widest text-muted-foreground">{caption}</p>
      </div>
    </div>
  );
};

/** Evidence capture slot: camera on mobile, file picker on desktop. */
export const PhotoSlot = ({
  label,
  hint,
  value,
  onCapture,
}: {
  label: string;
  hint?: string;
  value?: string;
  onCapture: (dataUrl: string) => void;
}) => {
  const inputRef = useRef<HTMLInputElement | null>(null);
  const inputId = useId();

  const handleFile = async (file: File | undefined): Promise<void> => {
    if (!file) return;
    try {
      const dataUrl = await compressImage(file);
      onCapture(dataUrl);
    } catch (error) {
      console.warn("No se pudo procesar la fotografía", error);
    }
  };

  return (
    <div>
      <input
        ref={inputRef}
        id={inputId}
        type="file"
        accept="image/*"
        capture="environment"
        className="hidden"
        onChange={(event) => void handleFile(event.target.files?.[0])}
      />
      <button
        type="button"
        onClick={() => inputRef.current?.click()}
        className={cn(
          "press relative flex aspect-[4/3] w-full flex-col items-center justify-center gap-1.5 overflow-hidden rounded-2xl border text-center",
          value ? "border-primary/60 bg-primary/5" : "border-dashed border-border bg-secondary/30",
        )}
      >
        {value ? (
          <>
            <img src={value} alt={label} className="absolute inset-0 size-full object-cover opacity-70" />
            <span className="relative grid size-9 place-items-center rounded-full bg-primary text-primary-foreground">
              <Check className="size-5" strokeWidth={3} />
            </span>
            <span className="relative rounded-full bg-background/80 px-2 py-0.5 text-[0.68rem] font-semibold">
              {label}
            </span>
          </>
        ) : (
          <>
            <Camera className="size-7 text-muted-foreground" />
            <span className="px-2 text-xs font-semibold leading-tight">{label}</span>
            {hint && <span className="px-2 text-[0.65rem] text-muted-foreground">{hint}</span>}
          </>
        )}
      </button>
    </div>
  );
};

export const BigButton = ({
  children,
  onClick,
  disabled,
  tone = "primary",
  icon,
  type = "button",
}: {
  children: ReactNode;
  onClick?: () => void;
  disabled?: boolean;
  tone?: "primary" | "outline" | "danger";
  icon?: ReactNode;
  type?: "button" | "submit";
}) => {
  const toneClass = {
    primary: "bg-primary text-primary-foreground volt-glow",
    outline: "border border-border bg-secondary/50 text-foreground",
    danger: "bg-destructive text-destructive-foreground",
  }[tone];

  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className={cn(
        "press flex h-16 w-full items-center justify-center gap-2.5 rounded-2xl text-base font-bold tracking-tight disabled:pointer-events-none disabled:opacity-40",
        toneClass,
      )}
    >
      {icon}
      {children}
    </button>
  );
};
