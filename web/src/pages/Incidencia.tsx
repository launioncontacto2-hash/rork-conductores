import { CarFront, Send, ShieldAlert, Wrench } from "lucide-react";
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { toast } from "sonner";

import { BigButton, PhotoSlot, ScreenHeader } from "@/components/Pieces";
import { Textarea } from "@/components/ui/textarea";
import { clockSeconds, dateShort } from "@/lib/format";
import type { IncidentKind } from "@/lib/types";
import { cn } from "@/lib/utils";
import { useFleet } from "@/store/fleet";

const KINDS: { id: IncidentKind; label: string; icon: typeof CarFront; hint: string }[] = [
  { id: "accident", label: "Accidente", icon: ShieldAlert, hint: "Con terceros o daños mayores" },
  { id: "damage", label: "Daño", icon: CarFront, hint: "Golpes, rayones, cristales" },
  { id: "mechanical", label: "Falla mecánica", icon: Wrench, hint: "Frenos, carga, suspensión" },
];

const Incidencia = () => {
  const { driver, now, activeVehicle, reportIncident, pushNotice } = useFleet();
  const navigate = useNavigate();

  const [kind, setKind] = useState<IncidentKind>("damage");
  const [description, setDescription] = useState<string>("");
  const [photos, setPhotos] = useState<(string | undefined)[]>([undefined, undefined, undefined]);

  const submit = (): void => {
    if (description.trim().length < 10) {
      toast.error("Describe la incidencia", { description: "Agrega al menos una frase con el detalle." });
      return;
    }
    const attached = photos.filter((photo): photo is string => Boolean(photo));
    reportIncident({ kind, description: description.trim(), photos: attached });
    pushNotice({
      kind: "station",
      title: "Incidencia enviada a la estación",
      body: `Tu reporte de ${KINDS.find((item) => item.id === kind)?.label.toLowerCase()} quedó en revisión.`,
    });
    toast.success("Incidencia reportada", { description: "El supervisor de estación fue notificado." });
    navigate("/turno", { replace: true });
  };

  return (
    <div className="pb-6">
      <ScreenHeader
        title="Reporte de incidencias"
        subtitle={activeVehicle ? `${activeVehicle.internalNumber} · ${activeVehicle.plates}` : driver.station}
        onBack={() => navigate("/turno")}
      />

      <div className="space-y-5 px-4 pt-5">
        <section className="space-y-2">
          {KINDS.map((item) => {
            const Icon = item.icon;
            const isActive = kind === item.id;
            return (
              <button
                key={item.id}
                type="button"
                onClick={() => setKind(item.id)}
                className={cn(
                  "press flex w-full items-center gap-3 rounded-2xl border p-4 text-left",
                  isActive ? "border-destructive/60 bg-destructive/10" : "border-border/70 bg-secondary/35",
                )}
              >
                <span
                  className={cn(
                    "grid size-11 shrink-0 place-items-center rounded-xl",
                    isActive ? "bg-destructive/20 text-destructive" : "bg-background/60 text-muted-foreground",
                  )}
                >
                  <Icon className="size-5" />
                </span>
                <span className="flex-1">
                  <span className="block text-sm font-bold">{item.label}</span>
                  <span className="block text-xs text-muted-foreground">{item.hint}</span>
                </span>
                <span
                  className={cn(
                    "size-5 rounded-full border-2",
                    isActive ? "border-destructive bg-destructive" : "border-border",
                  )}
                />
              </button>
            );
          })}
        </section>

        <section>
          <p className="label-caps mb-2">Comentarios</p>
          <Textarea
            value={description}
            onChange={(event) => setDescription(event.target.value)}
            rows={5}
            placeholder="Describe qué ocurrió, dónde y si la unidad sigue operable."
            className="rounded-2xl text-base"
          />
        </section>

        <section>
          <p className="label-caps mb-2">Fotografías</p>
          <div className="grid grid-cols-3 gap-2">
            {photos.map((photo, index) => (
              <PhotoSlot
                key={index}
                label={`Foto ${index + 1}`}
                value={photo}
                onCapture={(dataUrl) =>
                  setPhotos((prev) => prev.map((item, position) => (position === index ? dataUrl : item)))
                }
              />
            ))}
          </div>
        </section>

        <p className="panel-flat p-3 text-[0.7rem] leading-relaxed text-muted-foreground">
          Se registra automáticamente {dateShort(now)} · {clockSeconds(now)} · {driver.name}
          {activeVehicle ? ` · ${activeVehicle.internalNumber}` : ""}
        </p>

        <BigButton tone="danger" onClick={submit} icon={<Send className="size-5" />}>
          Enviar reporte
        </BigButton>
      </div>
    </div>
  );
};

export default Incidencia;
