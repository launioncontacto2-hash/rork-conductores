import path from "path";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const fallback = "Pendiente de despliegue";
const value = (input: string | undefined) => input?.trim() || undefined;
const normalizeBranchSlug = (branch: string) => branch
  .trim()
  .toLowerCase()
  .replace(/\//g, "-")
  .replace(/[^a-z0-9-]+/g, "-")
  .replace(/-+/g, "-")
  .replace(/^-|-$/g, "");
const projectSlug = "dori-console-test";

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => ({
  define: (() => {
    const sourceBranch = value(process.env.VITE_DORI_CONSOLE_SOURCE_BRANCH) ?? value(process.env.CF_PAGES_BRANCH);
    const sourceSha = value(process.env.VITE_DORI_CONSOLE_SOURCE_SHA) ?? value(process.env.CF_PAGES_COMMIT_SHA);
    const deploymentUrl = value(process.env.VITE_DORI_CONSOLE_DEPLOYMENT_URL) ?? value(process.env.CF_PAGES_URL);
    const canonicalSha = value(process.env.VITE_DORI_CONSOLE_CANONICAL_SHA)
      ?? (sourceBranch === "integration/dori-test" ? sourceSha : undefined);
    const branchAlias = value(process.env.VITE_DORI_CONSOLE_BRANCH_ALIAS)
      ?? (sourceBranch ? `https://${normalizeBranchSlug(sourceBranch)}.${projectSlug}.pages.dev` : undefined);
    const cloudflareBuild = Boolean(sourceBranch && sourceSha && deploymentUrl);
    const deployedAt = value(process.env.VITE_DORI_CONSOLE_DEPLOYED_AT)
      ?? (cloudflareBuild ? new Date().toISOString() : undefined);
    return {
      "import.meta.env.VITE_DORI_CONSOLE_SOURCE_BRANCH": JSON.stringify(sourceBranch ?? fallback),
      "import.meta.env.VITE_DORI_CONSOLE_SOURCE_SHA": JSON.stringify(sourceSha ?? fallback),
      "import.meta.env.VITE_DORI_CONSOLE_DEPLOYMENT_URL": JSON.stringify(deploymentUrl ?? fallback),
      "import.meta.env.VITE_DORI_CONSOLE_CANONICAL_SHA": JSON.stringify(canonicalSha ?? fallback),
      "import.meta.env.VITE_DORI_CONSOLE_BRANCH_ALIAS": JSON.stringify(branchAlias ?? fallback),
      "import.meta.env.VITE_DORI_CONSOLE_DEPLOYED_AT": JSON.stringify(deployedAt ?? fallback),
    };
  })(),
  server: {
    host: "::",
    port: 8080,
    hmr: {
      overlay: false,
    },
  },
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(import.meta.dirname, "./src"),
    },
  },
  // Expose both VITE_* (Vite default) and EXPO_PUBLIC_* (Rork's cross-platform
  // public-env convention, written by tools like getOrCreateAuthConfig).
  envPrefix: ["VITE_", "EXPO_PUBLIC_"],
}));
