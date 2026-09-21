const deploymentFallback = (value: string | undefined) => value?.trim() || "Pendiente de despliegue";

export const CONSOLE_RELEASE = {
  version: "1.0.0",
  build: "1001",
  validationStatus: "CANDIDATE",
  lifecycle: "ACTIVE",
  environment: "TEST",
  previousBuild: "Ninguno — baseline inicial",
  backendBaseline: "TEST · yyxzuiantrmoyozetswv",
  rollbackCompatibility: "REQUIRES REVIEW",
  changeSummary: "Recuperación de alta de unidades TEST; preservación de Asignar unidad; homologación visual del login mediante video aprobado; versionado formal de Consola.",
  deployment: {
    sourceBranch: deploymentFallback(import.meta.env.VITE_DORI_CONSOLE_SOURCE_BRANCH),
    sourceSha: deploymentFallback(import.meta.env.VITE_DORI_CONSOLE_SOURCE_SHA),
    canonicalSha: deploymentFallback(import.meta.env.VITE_DORI_CONSOLE_CANONICAL_SHA),
    deploymentUrl: deploymentFallback(import.meta.env.VITE_DORI_CONSOLE_DEPLOYMENT_URL),
    branchAlias: deploymentFallback(import.meta.env.VITE_DORI_CONSOLE_BRANCH_ALIAS),
    deployedAt: deploymentFallback(import.meta.env.VITE_DORI_CONSOLE_DEPLOYED_AT),
  },
} as const;
