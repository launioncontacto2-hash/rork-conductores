import { CalendarClock, CheckCircle2 } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { toast } from "sonner";

import { BigButton, PhotoSlot, ScreenHeader } from "@/components/Pieces";
import { clockSeconds, dateShort, firstName, lateText } from "@/lib/format";
import { paybackWindowLabel } from "@/lib/schedule";
import type { PhotoSlotId } from "@/lib/types";
import { useFleet } from "@/store/fleet";

const SLOTS: { id: PhotoSlotId; label: string; hint: string }[] = [
  { id: "odometer", label: "Odómetro", hint: "Lectura completa y legible" },
  { id: "battery", label: "Nivel de batería", hint: "Tablero encendido" },
  { id: "front", label: "Frente", hint: "Placa visible" },
  { id: "left", label: "Lateral izquierdo", hint: "Cuerpo completo" },
  { id: "right", label: "Lateral derecho", hint: "Cuerpo completo" },
  { id: "rear", label: "Trasera", hint: "Cajuela y micas" },
];

const Inspeccion = () => {
  const { driver, now, activeShift, activeVehicle, saveInspectionPhoto } = useFleet();
  const navigate = useNavigate();

  if (!activeShift || !activeVehicle) {
    return (
      <div className="px-4 pt-6">
        <ScreenHeader title="Registro de inicio" onBack={() => navigate("/turno")} />
        <p className="mt-6 text-sm text-muted-foreground">
          No hay turno activo. Escanea el QR de tu unidad para iniciar el registro.
        </p>
      </div>
    );
  }

  const captured = SLOTS.filter((slot) => activeShift.photos[slot.id]).length;
  const isComplete = captured === SLOTS.length;

  const finish = (): void => {
    toast.success("Registro de inicio guardado", {
      description: `${SLOTS.length} fotografías archivadas en el historial de ${activeVehicle.internalNumber}.`,
    });
    if (activeShift.lateMinutes > 0) {
      toast.warning(`${firstName(driver.name)}, tienes un atraso de ${lateText(activeShift.lateMinutes)} minutos.`, {
        description: `Recupéralos mañana en tu ventana de ${paybackWindowLabel(driver.shift.slot)}.`,
        duration: 8000,
      });
    }
    navigate("/turno", { replace: true });
  };

  return (
    <div className="pb-6">
      <ScreenHeader
        title="Registro de inicio de turno"
        subtitle={`${captured} de ${SLOTS.length} evidencias`}
        onBack={() => navigate("/turno")}
      />

      <div className="space-y-5 px-4 pt-5">
        <section className="panel-flat p-4">
          <p className="label-caps flex items-center gap-1.5">
            <CalendarClock className="size-3.5" /> Registro automático
          </p>
          <dl className="mt-3 grid grid-cols-2 gap-3 text-sm">
            {[
              { label: "Fecha", value: dateShort(now) },
              { label: "Hora", value: clockSeconds(now) },
              { label: "Conductor", value: driver.name },
              { label: "Vehículo", value: `${activeVehicle.internalNumber} · ${activeVehicle.plates}` },
            ].map((row) => (
              <div key={row.label}>
                <dt className="label-caps">{row.label}</dt>
                <dd className="tabular mt-0.5 font-bold leading-tight">{row.value}</dd>
              </div>
            ))}
          </dl>
        </section>

        <div className="grid grid-cols-2 gap-3">
          {SLOTS.map((slot) => (
            <PhotoSlot
              key={slot.id}
              label={slot.label}
              hint={slot.hint}
              value={activeShift.photos[slot.id]}
              onCapture={(dataUrl) => saveInspectionPhoto(slot.id, dataUrl)}
            />
          ))}
        </div>

        <p className="text-xs leading-relaxed text-muted-foreground">
          Las fotografías se archivan en el historial de la unidad. En la siguiente versión, el odómetro se leerá
          automáticamente por OCR.
        </p>

        <BigButton onClick={finish} disabled={!isComplete} icon={<CheckCircle2 className="size-5" />}>
          {isComplete ? "Confirmar inicio de turno" : `Faltan ${SLOTS.length - captured} fotografías`}
        </BigButton>
      </div>
    </div>
  );
};

export default Inspeccion;
