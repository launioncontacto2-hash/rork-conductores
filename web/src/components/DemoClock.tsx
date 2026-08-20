import { Clock4 } from "lucide-react";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { clock } from "@/lib/format";
import { SHIFT_WINDOWS } from "@/lib/schedule";
import { cn } from "@/lib/utils";
import { useFleet } from "@/store/fleet";

interface Preset {
  label: string;
  hint: string;
  /** Target minute of day, or null for the real device clock. */
  minutes: number | null;
}

const PRESETS: Preset[] = [
  { label: "Hora real", hint: "Reloj del dispositivo", minutes: null },
  { label: "05:05", hint: "Inicio a tiempo · matutino", minutes: SHIFT_WINDOWS.morning.startMinutes + 5 },
  { label: "05:35", hint: "Inicio con atraso", minutes: SHIFT_WINDOWS.morning.startMinutes + 35 },
  { label: "10:00", hint: "Turno activo", minutes: 10 * 60 },
  { label: "13:40", hint: "Cierre de turno", minutes: 13 * 60 + 40 },
  { label: "04:15", hint: "Pago de atraso", minutes: 4 * 60 + 15 },
];

/**
 * Demo-only clock control. The app always reads the device time; this offsets it
 * so every shift rule (late start, payback window, invalid shift) can be shown.
 */
export const DemoClock = ({ compact = false }: { compact?: boolean }) => {
  const { now, clockOffsetMinutes, setClockOffset } = useFleet();
  const [isOpen, setIsOpen] = useState<boolean>(false);

  const apply = (preset: Preset): void => {
    if (preset.minutes === null) {
      setClockOffset(0);
    } else {
      const real = new Date();
      const currentMinutes = real.getHours() * 60 + real.getMinutes();
      setClockOffset(preset.minutes - currentMinutes);
    }
    setIsOpen(false);
  };

  return (
    <>
      <button
        type="button"
        onClick={() => setIsOpen(true)}
        className={cn(
          "press flex items-center gap-2 rounded-full border border-border/70 bg-secondary/50 px-3 py-1.5 text-xs font-semibold",
          clockOffsetMinutes !== 0 && "border-warning/50 text-warning",
          compact && "px-2.5 py-1",
        )}
      >
        <Clock4 className="size-3.5" />
        <span className="tabular">{clock(now)}</span>
        {clockOffsetMinutes !== 0 && <span className="label-caps text-warning">demo</span>}
      </button>

      <Dialog open={isOpen} onOpenChange={setIsOpen}>
        <DialogContent className="max-w-sm rounded-3xl">
          <DialogHeader>
            <DialogTitle>Reloj de demostración</DialogTitle>
            <DialogDescription>
              Cambia la hora del dispositivo simulada para revisar cada regla de turno.
            </DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-2">
            {PRESETS.map((preset) => (
              <button
                key={preset.label}
                type="button"
                onClick={() => apply(preset)}
                className="press rounded-2xl border border-border/70 bg-secondary/40 p-3 text-left"
              >
                <p className="tabular text-base font-bold">{preset.label}</p>
                <p className="text-[0.7rem] leading-tight text-muted-foreground">{preset.hint}</p>
              </button>
            ))}
          </div>
          <Button variant="ghost" onClick={() => setIsOpen(false)} className="mt-1 h-11 rounded-xl">
            Cerrar
          </Button>
        </DialogContent>
      </Dialog>
    </>
  );
};
