import path from "path";

import react from "@vitejs/plugin-react";
import { playwright } from "@vitest/browser-playwright";
import { defineConfig } from "vitest/config";

const localChromium = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;

export default defineConfig({
  plugins: [react()],
  optimizeDeps: {
    include: [
      "@radix-ui/react-tooltip",
      "@radix-ui/react-alert-dialog",
      "@tanstack/react-query",
      "next-themes",
      "react",
      "react-dom",
      "react-router-dom",
      "sonner",
    ],
  },
  test: {
    globals: true,
    include: ["src/**/*.browser.{test,spec}.{ts,tsx}"],
    browser: {
      enabled: true,
      headless: true,
      provider: playwright({
        launchOptions: localChromium ? { executablePath: localChromium } : undefined,
      }),
      instances: [{ browser: "chromium" }],
    },
  },
  resolve: {
    alias: { "@": path.resolve(import.meta.dirname, "./src") },
  },
});
