import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const root = resolve(process.cwd(), "public/version.json");
const firstDefined = (...values) => values.find((value) => typeof value === "string" && value.trim());
const payload = { environment: "TEST", version: "1.0.0", build: firstDefined(process.env.VITE_DORI_CONSOLE_BUILD) || "1002", sourceSha: firstDefined(process.env.VITE_DORI_CONSOLE_SOURCE_SHA, process.env.CF_PAGES_COMMIT_SHA, process.env.GITHUB_SHA) || "unknown", sourceBranch: firstDefined(process.env.VITE_DORI_CONSOLE_SOURCE_BRANCH, process.env.CF_PAGES_BRANCH, process.env.GITHUB_REF_NAME) || "unknown", deploymentUrl: firstDefined(process.env.VITE_DORI_CONSOLE_DEPLOYMENT_URL, process.env.CF_PAGES_URL) || "unknown", deployedAt: new Date().toISOString() };

try { await writeFile(root, `${JSON.stringify(payload, null, 2)}\n`, "utf8"); } catch { console.warn("version.json no pudo regenerarse en este entorno; se conserva el fallback versionado."); }
