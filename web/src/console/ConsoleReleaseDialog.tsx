import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { CONSOLE_RELEASE } from "@/console/consoleRelease";

export const ConsoleReleaseDialog = () => {
  const [open, setOpen] = useState(false);
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="link" className="mt-1 h-auto p-0 text-xs text-muted-foreground">Versión {CONSOLE_RELEASE.version} · Build {CONSOLE_RELEASE.build} ›</Button>
      </DialogTrigger>
      <DialogContent className="max-w-lg rounded-3xl">
        <DialogHeader>
          <DialogTitle>Información de versión</DialogTitle>
          <DialogDescription>Metadata de release de Consola DORI.</DialogDescription>
        </DialogHeader>
        <dl className="grid gap-3 text-sm sm:grid-cols-2">
          <div><dt className="label-caps">Versión</dt><dd>{CONSOLE_RELEASE.version}</dd></div>
          <div><dt className="label-caps">Build</dt><dd>{CONSOLE_RELEASE.build}</dd></div>
          <div><dt className="label-caps">Validation status</dt><dd>{CONSOLE_RELEASE.validationStatus}</dd></div>
          <div><dt className="label-caps">Lifecycle</dt><dd>{CONSOLE_RELEASE.lifecycle}</dd></div>
          <div><dt className="label-caps">Environment</dt><dd>{CONSOLE_RELEASE.environment}</dd></div>
          <div><dt className="label-caps">Deployment</dt><dd>Pendiente de despliegue</dd></div>
        </dl>
      </DialogContent>
    </Dialog>
  );
};
