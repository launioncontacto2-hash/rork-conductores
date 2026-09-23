import { useEffect, useState } from "react";
import { RefreshCw } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { CONSOLE_RELEASE } from "@/console/consoleRelease";

type PublishedVersion = { build?: string; deployedAt?: string };

const formatDate = (value: string) => {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString("es-MX", { dateStyle: "short", timeStyle: "short" });
};

export const ConsoleReleaseStatus = () => {
  const [published, setPublished] = useState<PublishedVersion | null>(null);
  const [stale, setStale] = useState(false);

  useEffect(() => {
    let active = true;
    const check = async () => {
      try {
        const response = await fetch(`/version.json?ts=${Date.now()}`, { cache: "no-store" });
        if (!response.ok) return;
        const next = await response.json() as PublishedVersion;
        if (!active) return;
        setPublished(next);
        setStale(Boolean(next.build && next.build !== CONSOLE_RELEASE.build));
      } catch {
        // The release dialog remains the source of truth if metadata is unavailable.
      }
    };
    void check();
    const timer = window.setInterval(check, 60_000);
    return () => { active = false; window.clearInterval(timer); };
  }, []);

  const date = published?.deployedAt || CONSOLE_RELEASE.deployment.deployedAt;
  return (
    <div className="mt-2 flex flex-wrap items-center gap-2 text-xs text-muted-foreground" data-testid="console-release-status">
      <span className="font-semibold">DORI CONSOLA · TEST</span>
      <span>Versión {CONSOLE_RELEASE.version} · Build {published?.build || CONSOLE_RELEASE.build}</span>
      {date !== "Pendiente de despliegue" && <span>Publicada: {formatDate(date)}</span>}
      <Badge variant="outline" className={stale ? "border-amber-400/50 text-amber-300" : "border-emerald-400/50 text-emerald-300"}>
        {stale ? "● DESACTUALIZADA" : "● ACTUAL"}
      </Badge>
      {stale && <Button size="sm" variant="outline" className="h-7" onClick={() => window.location.reload()}><RefreshCw /> Actualizar</Button>}
    </div>
  );
};
