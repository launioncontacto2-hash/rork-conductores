import { useMemo, useState } from "react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

type Offer = {
  id: number;
  service: "UberX" | "Uber Comfort";
  pickupMinutes: number;
  pickupDistanceKm: number;
};

const initialOffer = (id: number): Offer => ({ id, service: "UberX", pickupMinutes: 8, pickupDistanceKm: 2.5 });

export const DoriTestWorkbench = () => {
  const [offers, setOffers] = useState<Offer[]>([initialOffer(1)]);
  const [destinationToStationKm, setDestinationToStationKm] = useState(0);
  const [destinationValue, setDestinationValue] = useState(0);
  const [batchStatus, setBatchStatus] = useState<"waiting" | "sent">("waiting");
  const updateOffer = (id: number, patch: Partial<Offer>) => setOffers((current) => current.map((offer) => offer.id === id ? { ...offer, ...patch } : offer));
  const resultLabel = useMemo(() => batchStatus === "sent" ? "Tanda enviada a DORI COPILOTO" : "Esperando envío", [batchStatus]);

  return (
    <section id="uber-test" className="grid gap-4 scroll-mt-4 lg:grid-cols-[1.35fr_1fr]">
      <Card className="panel">
        <CardHeader>
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div><CardTitle className="text-lg">UBER Test</CardTitle><CardDescription>Simulación TEST · hasta 10 ofertas · sin escritura de producción.</CardDescription></div>
            <Badge variant="outline" className="border-amber-400/50 text-amber-300">DORI COPILOTO · {resultLabel}</Badge>
          </div>
        </CardHeader>
        <CardContent className="space-y-3">
          {offers.map((offer, index) => (
            <div key={offer.id} className="grid gap-2 rounded-lg border border-border/70 p-3 md:grid-cols-[auto_1fr_1fr_1fr] md:items-end">
              <span className="text-sm font-bold">Oferta {index + 1}</span>
              <label className="grid gap-1 text-xs font-semibold">Servicio<select className="h-10 rounded-md border border-border bg-background px-2 text-sm font-normal" value={offer.service} onChange={(event) => updateOffer(offer.id, { service: event.target.value as Offer["service"] })}><option>UberX</option><option>Uber Comfort</option></select></label>
              <label className="grid gap-1 text-xs font-semibold">Recogida (min)<input className="h-10 rounded-md border border-border bg-background px-2 text-sm font-normal" type="number" min="0" value={offer.pickupMinutes} onChange={(event) => updateOffer(offer.id, { pickupMinutes: Number(event.target.value) })} /></label>
              <label className="grid gap-1 text-xs font-semibold">Distancia (km)<input className="h-10 rounded-md border border-border bg-background px-2 text-sm font-normal" type="number" min="0" step="0.1" value={offer.pickupDistanceKm} onChange={(event) => updateOffer(offer.id, { pickupDistanceKm: Number(event.target.value) })} /></label>
            </div>
          ))}
          <div className="flex flex-wrap gap-2">
            <Button variant="outline" disabled={offers.length >= 10} onClick={() => setOffers((current) => [...current, initialOffer(current.length + 1)])}>Agregar oferta</Button>
            <Button onClick={() => setBatchStatus("sent")}>Enviar tanda TEST</Button>
          </div>
          {batchStatus === "sent" && <p className="text-xs text-muted-foreground">La tanda está preparada localmente; el resultado operativo aparecerá cuando el backend TEST responda.</p>}
        </CardContent>
      </Card>

      <Card className="panel">
        <CardHeader><CardTitle className="text-lg">Copiloto TEST</CardTitle><CardDescription>Editor avanzado de simulación; estos campos no forman parte de UBER Test.</CardDescription></CardHeader>
        <CardContent className="space-y-3">
          <Badge className="bg-amber-400 text-black hover:bg-amber-400">SIMULACIÓN TEST</Badge>
          <label className="grid gap-1 text-sm font-semibold">Destino a estación (km)<input className="h-10 rounded-md border border-border bg-background px-3 font-normal" type="number" min="0" step="0.1" value={destinationToStationKm} onChange={(event) => setDestinationToStationKm(Number(event.target.value))} /></label>
          <label className="grid gap-1 text-sm font-semibold">Valor destino<input className="h-10 rounded-md border border-border bg-background px-3 font-normal" type="number" min="0" step="0.01" value={destinationValue} onChange={(event) => setDestinationValue(Number(event.target.value))} /></label>
          <p className="text-xs text-muted-foreground">Metadatos Copiloto preparados: destinationToStationKm, destinationValue.</p>
        </CardContent>
      </Card>
    </section>
  );
};
