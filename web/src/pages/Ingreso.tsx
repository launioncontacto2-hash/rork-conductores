import { CircleDollarSign, Plus, Save } from "lucide-react";
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { toast } from "sonner";

import { BigButton, PhotoSlot, ScreenHeader } from "@/components/Pieces";
import { Input } from "@/components/ui/input";
import { mxn } from "@/lib/format";
import { goalsFor } from "@/lib/schedule";
import { goalProgress } from "@/lib/selectors";
import type { IncomePlatform } from "@/lib/types";
import { cn } from "@/lib/utils";
import { useFleet } from "@/store/fleet";

const PLATFORMS: IncomePlatform[] = ["Uber", "DiDi", "Efectivo", "Otro"];

const Ingreso = () => {
  const { driver, now, incomes, history, activeShift, registerIncome } = useFleet();
  const navigate = useNavigate();

  const [amount, setAmount] = useState<string>("");
  const [trips, setTrips] = useState<string>("");
  const [platform, setPlatform] = useState<IncomePlatform>("Uber");
  const [evidence, setEvidence] = useState<string | undefined>(undefined);

  const goals = goalsFor(driver.shift.group);
  const progress = goalProgress(driver.shift.group, incomes, history, activeShift, now);
  const amountValue = Number(amount);
  const projected = progress.earnedToday + (Number.isFinite(amountValue) ? amountValue : 0);

  const save = (): void => {
    if (!Number.isFinite(amountValue) || amountValue <= 0) {
      toast.error("Captura el monto del ingreso");
      return;
    }
    registerIncome({
      amountMxn: amountValue,
      trips: Number(trips) || 0,
      platform,
      evidence,
    });
    toast.success("Ingreso registrado", {
      description: evidence ? "Evidencia guardada en tu historial." : "Recuerda adjuntar la captura de pantalla.",
    });
    navigate("/turno", { replace: true });
  };

  return (
    <div className="pb-6">
      <ScreenHeader title="Registro de ingresos" subtitle="Captura diaria con evidencia" onBack={() => navigate("/turno")} />

      <div className="space-y-5 px-4 pt-5">
        <section className="panel p-5">
          <p className="label-caps flex items-center gap-1.5">
            <CircleDollarSign className="size-3.5" /> Monto del ingreso
          </p>
          <Input
            value={amount}
            onChange={(event) => setAmount(event.target.value.replace(/[^\d.]/g, ""))}
            inputMode="decimal"
            placeholder="0"
            className="tabular mt-3 h-20 rounded-2xl border-0 bg-transparent text-center text-4xl font-black focus-visible:ring-0"
          />
          <div className="flex flex-wrap justify-center gap-2">
            {[200, 400, 800, 1520].map((quick) => (
              <button
                key={quick}
                type="button"
                onClick={() => setAmount(String((Number(amount) || 0) + quick))}
                className="press flex items-center gap-1 rounded-full border border-border/70 bg-secondary/40 px-3 py-1.5 text-xs font-bold"
              >
                <Plus className="size-3" />
                {mxn(quick)}
              </button>
            ))}
          </div>
          <p className="mt-4 text-center text-xs text-muted-foreground">
            Acumulado del día {mxn(projected)} de {mxn(goals.dailyMxn)}
          </p>
        </section>

        <section className="space-y-3">
          <div>
            <p className="label-caps mb-2">Plataforma</p>
            <div className="grid grid-cols-4 gap-2">
              {PLATFORMS.map((item) => (
                <button
                  key={item}
                  type="button"
                  onClick={() => setPlatform(item)}
                  className={cn(
                    "press h-12 rounded-xl border text-xs font-bold",
                    platform === item
                      ? "border-primary bg-primary/15 text-primary"
                      : "border-border/70 bg-secondary/40 text-muted-foreground",
                  )}
                >
                  {item}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="label-caps mb-1.5 block" htmlFor="trips">
              Viajes realizados
            </label>
            <Input
              id="trips"
              value={trips}
              onChange={(event) => setTrips(event.target.value.replace(/[^\d]/g, "").slice(0, 3))}
              inputMode="numeric"
              placeholder="14"
              className="tabular h-16 rounded-2xl text-center text-2xl font-black"
            />
          </div>

          <div>
            <p className="label-caps mb-2">Captura de pantalla</p>
            <PhotoSlot
              label="Adjuntar evidencia"
              hint="Resumen de ganancias de la plataforma"
              value={evidence}
              onCapture={setEvidence}
            />
          </div>
        </section>

        <BigButton onClick={save} icon={<Save className="size-5" />}>
          Guardar ingreso
        </BigButton>
      </div>
    </div>
  );
};

export default Ingreso;
