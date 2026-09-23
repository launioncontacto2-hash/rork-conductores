import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const root = resolve(process.cwd(), "public/version.json");
const firstDefined = (...values) => values.find((value) => value?.trim())?.trim();
const value = {
  environment: "TEST",
  version: "1.0.0",
  build: process.env.VITE_DORI_CONSOLE_BUILD || process.env.GITHUB_RUN_NUMBER || "1001",
  sourceSha: firstDefined(process.env.VITE_DORI_CONSOLE_SOURCE_SHA, process.env.CF_PAGES_COMMIT_SHA, process.env.GITHUB_SHA) || "unknown",
  sourceBranch: firstDefined(process.env.VITE_DORI_CONSOLE_SOURCE_BRANCH, process.env.CF_PAGES_BRANCH, process.env.GITHUB_REF_NAME) || "unknown",
  deploymentUrl: firstDefined(process.env.VITE_DORI_CONSOLE_DEPLOYMENT_URL, process.env.CF_PAGES_URL) || "unknown",
  deployedAt: process.env.VITE_DORI_CONSOLE_DEPLOYED_AT || new Date().toISOString(),
};

try {
  await mkdir(dirname(root), { recursive: true });
  await writeFile(root, `${JSON.stringify(value, null, 2)}\n`, "utf8");
} catch (error) {
  if (error?.code !== "EPERM" && error?.code !== "EACCES") throw error;
  console.warn("version.json no pudo regenerarse en este entorno; se conserva el fallback versionado.");
}
