import { BadgeCheck, Gauge, PartyPopper, Route, Timer } from "lucide-react";
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { toast } from "sonner";

import { BigButton, PhotoSlot, ScreenHeader, StatTile } from "@/components/Pieces";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { durationText, firstName, km, mxn } from "@/lib/format";
import type { ShiftSummary } from "@/lib/types";
import { cn } from "@/lib/utils";
import { useFleet } from "@/store/fleet";

const Finalizar = () => {
  const { driver, activeShift, activeVehicle, estimatedKmDriven, finishShift, pushNotice } = useFleet();
  const navigate = useNavigate();

  const [odometer, setOdometer] = useState<string>("");
  const [battery, setBattery] = useState<string>("");
  const [photo, setPhoto] = useState<string | undefined>(undefined);
  const [confirmDelivery, setConfirmDelivery] = useState<boolean>(false);
  const [summary, setSummary] = useState<ShiftSummary | null>(null);

  if (!activeShift || !activeVehicle) {
    return (
      <div>
        <ScreenHeader title="Finalizar turno" onBack={() => navigate("/turno")} />
        <p className="px-4 pt-6 text-sm text-muted-foreground">No hay un turno activo por cerrar.</p>
      </div>
    );
  }

  const suggested = activeShift.startOdometerKm + estimatedKmDriven;

  const close = (): void => {
    const odometerValue = Number(odometer);
    const batteryValue = Number(battery);

    if (!Number.isFinite(odometerValue) || odometerValue < activeShift.startOdometerKm) {
      toast.error("Kilometraje final inválido", {
        description: `Debe ser mayor o igual a ${km(activeShift.startOdometerKm)}.`,
      });
      return;
    }
    if (!photo) {
      toast.error("Falta la fotografía final del odómetro");
      return;
    }
    if (!confirmDelivery) {
      toast.error("Confirma la entrega de la unidad");
      return;
    }

    const result = finishShift({
      endOdometerKm: odometerValue,
      endBatteryPct: Number.isFinite(batteryValue) && batteryValue > 0 ? batteryValue : 20,
      photo,
    });
    setSummary(result);

    // End-of-shift notifications, in the order defined by operations.
    toast.success(`${firstName(driver.name)}, tu turno ha finalizado. ¡Bien hecho!`, {
      description: "Ahora, vuelve a la estación.",
      duration: 7000,
    });
    if (result.missingMxn > 0) {
      toast.warning(`${firstName(driver.name)}, faltó ${mxn(result.missingMxn)} para llegar a la meta del día`, {
        duration: 8000,
      });
    }
    if (result.missingTrips > 0) {
      toast.warning(`${firstName(driver.name)}, faltaron ${result.missingTrips} viajes para la meta`, {
        description: "Recupéralos mañana.",
        duration: 8000,
      });
    }
    pushNotice({
      kind: "station",
      title: "Turno cerrado",
      body: `Entregaste ${activeVehicle.internalNumber} con ${km(odometerValue)}. Duración ${durationText(result.durationMinutes)}.`,
    });
  };

  return (
    <div className="pb-6">
      <ScreenHeader
        title="Finalización de turno"
        subtitle={`${activeVehicle.internalNumber} · ${activeVehicle.plates}`}
        onBack={() => navigate("/turno")}
      />

      <div className="space-y-5 px-4 pt-5">
        <div className="grid grid-cols-2 gap-3">
          <StatTile label="Odómetro inicial" value={km(activeShift.startOdometerKm)} icon={<Gauge className="size-4 text-muted-foreground" />} />
          <StatTile label="Km estimados" value={km(estimatedKmDriven)} hint="GPS simulado" icon={<Route className="size-4 text-muted-foreground" />} />
        </div>

        <section>
          <label className="label-caps mb-1.5 block" htmlFor="final-odometer">
            Kilometraje final
          </label>
          <Input
            id="final-odometer"
            value={odometer}
            onChange={(event) => setOdometer(event.target.value.replace(/[^\d]/g, ""))}
            inputMode="numeric"
            placeholder={String(suggested)}
            className="tabular h-16 rounded-2xl text-center text-2xl font-black"
          />
          <button
            type="button"
            onClick={() => setOdometer(String(suggested))}
            className="press mt-2 rounded-full border border-border/70 bg-secondary/40 px-3 py-1.5 text-xs font-semibold"
          >
            Usar estimado {km(suggested)}
          </button>
        </section>

        <section>
          <label className="label-caps mb-1.5 block" htmlFor="final-battery">
            Nivel de batería de entrega
          </label>
          <Input
            id="final-battery"
            value={battery}
            onChange={(event) => setBattery(event.target.value.replace(/[^\d]/g, "").slice(0, 3))}
            inputMode="numeric"
            placeholder="28"
            className="tabular h-16 rounded-2xl text-center text-2xl font-black"
          />
        </section>

        <section>
          <p className="label-caps mb-2">Fotografía final del odómetro</p>
          <PhotoSlot label="Odómetro final" hint="Lectura legible" value={photo} onCapture={setPhoto} />
        </section>

        <button
          type="button"
          onClick={() => setConfirmDelivery((prev) => !prev)}
          className={cn(
            "press flex w-full items-center gap-3 rounded-2xl border p-4 text-left",
            confirmDelivery ? "border-primary/60 bg-primary/10" : "border-border/70 bg-secondary/35",
          )}
        >
          <span
            className={cn(
              "grid size-7 shrink-0 place-items-center rounded-lg border-2",
              confirmDelivery ? "border-primary bg-primary text-primary-foreground" : "border-border",
            )}
          >
            {confirmDelivery && <BadgeCheck className="size-4" strokeWidth={3} />}
          </span>
          <span className="text-sm font-semibold leading-snug">
            Confirmo la entrega de la unidad en {activeVehicle.station} conectada al cargador.
          </span>
        </button>

        <BigButton onClick={close} icon={<BadgeCheck className="size-5" />}>
          Cerrar turno
        </BigButton>
      </div>

      <Dialog
        open={summary !== null}
        onOpenChange={(open) => {
          if (!open) {
            setSummary(null);
            navigate("/turno", { replace: true });
          }
        }}
      >
        <DialogContent className="max-w-sm rounded-3xl">
          <DialogHeader>
            <div className="mx-auto grid size-14 place-items-center rounded-2xl bg-primary/15 text-primary volt-glow">
              <PartyPopper className="size-8" />
            </div>
            <DialogTitle className="text-center">Turno finalizado</DialogTitle>
            <DialogDescription className="text-center">
              {firstName(driver.name)}, tu turno ha finalizado. ¡Bien hecho!, ahora, vuelve a la estación.
            </DialogDescription>
          </DialogHeader>

          {summary && (
            <>
              <div className="grid grid-cols-2 gap-3">
                <StatTile label="Kilómetros" value={km(summary.kmDriven)} tone="primary" />
                <StatTile
                  label="Duración"
                  value={durationText(summary.durationMinutes)}
                  icon={<Timer className="size-4 text-muted-foreground" />}
                />
                <StatTile label="Ingresos" value={mxn(summary.earningsMxn)} />
                <StatTile label="Viajes" value={`${summary.trips} / 14`} />
              </div>

              {summary.missingMxn > 0 && (
                <p className="rounded-2xl border border-warning/40 bg-warning/10 p-3 text-sm font-semibold leading-snug">
                  {firstName(driver.name)}, faltó {mxn(summary.missingMxn)} para llegar a la meta del día.
                </p>
              )}
              {summary.missingTrips > 0 && (
                <p className="rounded-2xl border border-warning/40 bg-warning/10 p-3 text-sm font-semibold leading-snug">
                  {firstName(driver.name)}, faltaron {summary.missingTrips} viajes para la meta. Recupéralos mañana.
                </p>
              )}
            </>
          )}

          <BigButton
            onClick={() => {
              setSummary(null);
              navigate("/turno", { replace: true });
            }}
          >
            Entendido
          </BigButton>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default Finalizar;
