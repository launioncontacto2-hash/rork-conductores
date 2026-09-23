export const RELEASE_FALLBACK = "Pendiente de despliegue";

export interface ReleaseBuildInputs {
  build?: string;
  sourceBranch?: string;
  sourceSha?: string;
  deploymentUrl?: string;
  canonicalSha?: string;
  branchAlias?: string;
  deployedAt?: string;
}

const deploymentFallback = (value: string | undefined) => value?.trim() || RELEASE_FALLBACK;

export const normalizeBranchSlug = (branch: string) => branch
  .trim()
  .toLowerCase()
  .replace(/\//g, "-")
  .replace(/[^a-z0-9-]+/g, "-")
  .replace(/-+/g, "-")
  .replace(/^-|-$/g, "");

export const resolveReleaseBuildMetadata = (inputs: ReleaseBuildInputs) => {
  const sourceBranch = deploymentFallback(inputs.sourceBranch);
  const sourceSha = deploymentFallback(inputs.sourceSha);
  const deploymentUrl = deploymentFallback(inputs.deploymentUrl);
  const canonicalSha = inputs.canonicalSha?.trim()
    || (sourceBranch === "integration/dori-test" && sourceSha !== RELEASE_FALLBACK ? sourceSha : RELEASE_FALLBACK);
  const branchAlias = deploymentFallback(inputs.branchAlias);
  const deployedAt = deploymentFallback(inputs.deployedAt);
  return { sourceBranch, sourceSha, deploymentUrl, canonicalSha, branchAlias, deployedAt };
};

const injected = {
  build: import.meta.env.VITE_DORI_CONSOLE_BUILD,
  sourceBranch: import.meta.env.VITE_DORI_CONSOLE_SOURCE_BRANCH,
  sourceSha: import.meta.env.VITE_DORI_CONSOLE_SOURCE_SHA,
  deploymentUrl: import.meta.env.VITE_DORI_CONSOLE_DEPLOYMENT_URL,
  canonicalSha: import.meta.env.VITE_DORI_CONSOLE_CANONICAL_SHA,
  branchAlias: import.meta.env.VITE_DORI_CONSOLE_BRANCH_ALIAS,
  deployedAt: import.meta.env.VITE_DORI_CONSOLE_DEPLOYED_AT,
};

export const CONSOLE_RELEASE = {
  version: "1.0.0",
  build: injected.build?.trim() || "1001",
  validationStatus: "CANDIDATE",
  lifecycle: "ACTIVE",
  environment: "TEST",
  previousBuild: "Ninguno — baseline inicial",
  backendBaseline: "TEST · yyxzuiantrmoyozetswv",
  rollbackCompatibility: "REQUIRES REVIEW",
  changeSummary: "Recuperación de alta de unidades TEST; preservación de Asignar unidad; homologación visual del login mediante video aprobado; versionado formal de Consola.",
  deployment: resolveReleaseBuildMetadata(injected),
} as const;
