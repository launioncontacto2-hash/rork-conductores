import { useState } from "react";
import { CalendarClock, LoaderCircle } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { supabase } from "@/lib/supabase";

import {
  currentTestInstant,
  makePausedClockCommand,
  stationDateTimeInputValue,
  type TestClockRow,
} from "./testClock";

interface TestClockDialogProps {
  clock: TestClockRow | null | undefined;
  stationTimeZone: string;
  onApplied: () => Promise<unknown>;
}

export const TestClockDialog = ({ clock, stationTimeZone, onApplied }: TestClockDialogProps) => {
  const [open, setOpen] = useState(false);
  const [value, setValue] = useState("");
  const [isApplying, setIsApplying] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const changeOpen = (next: boolean) => {
    setOpen(next);
    setMessage(null);
    if (next && clock) {
      setValue(stationDateTimeInputValue(currentTestInstant(clock), stationTimeZone));
    }
  };

  const apply = async () => {
    if (!supabase || !clock || !value) return;
    setIsApplying(true);
    setMessage(null);
    try {
      const command = makePausedClockCommand(clock, value, stationTimeZone);
      const { error } = await supabase.rpc("update_test_clock", command);
      if (error) {
        if (error.code === "40001" || error.message.includes("revision_conflict")) {
          throw new Error("Otro dispositivo movió el reloj. Se recargó el estado; vuelve a aplicar la hora.");
        }
        throw new Error(error.message);
      }
      await onApplied();
      setOpen(false);
    } catch (error) {
      await onApplied();
      setMessage(error instanceof Error ? error.message : "No fue posible ajustar el reloj TEST.");
    } finally {
      setIsApplying(false);
    }
  };

  return (
    <>
      <Button variant="outline" onClick={() => changeOpen(true)} disabled={!clock}>
        <CalendarClock /> Ajustar reloj TEST
      </Button>
      <Dialog open={open} onOpenChange={changeOpen}>
        <DialogContent className="panel border-amber-400/30">
          <DialogHeader>
            <DialogTitle>Fecha y hora del entorno TEST</DialogTitle>
            <DialogDescription>
              Se interpreta en {stationTimeZone}. Al aplicar, el reloj queda pausado en el instante exacto y el iPhone lo recibe por Realtime.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-2">
            <label htmlFor="test-clock-value" className="label-caps">Fecha y hora de estación</label>
            <Input
              id="test-clock-value"
              type="datetime-local"
              step="1"
              value={value}
              onChange={(event) => setValue(event.target.value)}
              disabled={isApplying}
              className="[color-scheme:dark]"
            />
            <p className="text-xs text-muted-foreground">
              Solo el supervisor autenticado puede publicar este cambio. No modifica la hora real del teléfono.
            </p>
            {message && <p role="alert" className="text-sm font-semibold text-amber-300">{message}</p>}
          </div>

          <DialogFooter className="gap-2">
            <Button variant="ghost" onClick={() => changeOpen(false)} disabled={isApplying}>Cancelar</Button>
            <Button onClick={() => void apply()} disabled={!value || isApplying}>
              {isApplying ? <LoaderCircle className="animate-spin" /> : <CalendarClock />}
              Aplicar y pausar
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
};
