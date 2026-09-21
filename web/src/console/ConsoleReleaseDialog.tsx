import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { CONSOLE_RELEASE } from "@/console/consoleRelease";
import { useConsoleAuth } from "@/console/ConsoleAuth";

export const ConsoleReleaseDialog = () => {
  const { identity } = useConsoleAuth();
  const [open, setOpen] = useState(false);
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="link" className="mt-1 h-auto p-0 text-xs text-muted-foreground">Versión {CONSOLE_RELEASE.version} · Build {CONSOLE_RELEASE.build} ›</Button>
      </DialogTrigger>
      <DialogContent className="max-h-[85dvh] max-w-lg overflow-y-auto rounded-3xl">
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
          <div><dt className="label-caps">Station</dt><dd>{identity?.station_name ?? "Pendiente de despliegue"}</dd></div>
          <div><dt className="label-caps">Station code</dt><dd>{identity?.station_code ?? "Pendiente de despliegue"}</dd></div>
          <div><dt className="label-caps">Git branch</dt><dd className="break-all">{CONSOLE_RELEASE.deployment.sourceBranch}</dd></div>
          <div><dt className="label-caps">Git SHA</dt><dd className="break-all">{CONSOLE_RELEASE.deployment.sourceSha}</dd></div>
          <div><dt className="label-caps">Canonical at deploy</dt><dd className="break-all">{CONSOLE_RELEASE.deployment.canonicalSha}</dd></div>
          <div><dt className="label-caps">Deployment URL</dt><dd className="break-all">{CONSOLE_RELEASE.deployment.deploymentUrl}</dd></div>
          <div><dt className="label-caps">Branch alias</dt><dd className="break-all">{CONSOLE_RELEASE.deployment.branchAlias}</dd></div>
          <div><dt className="label-caps">Deployed / build timestamp</dt><dd className="break-all">{CONSOLE_RELEASE.deployment.deployedAt}</dd></div>
          <div><dt className="label-caps">Previous build</dt><dd>{CONSOLE_RELEASE.previousBuild}</dd></div>
          <div><dt className="label-caps">Backend baseline</dt><dd className="break-words">{CONSOLE_RELEASE.backendBaseline}</dd></div>
          <div><dt className="label-caps">Rollback compatibility</dt><dd>{CONSOLE_RELEASE.rollbackCompatibility}</dd></div>
          <div className="sm:col-span-2"><dt className="label-caps">Change summary</dt><dd className="break-words">{CONSOLE_RELEASE.changeSummary}</dd></div>
        </dl>
      </DialogContent>
    </Dialog>
  );
};
