import { defineConfig } from "@playwright/test";

const baseURL = (process.env.APP_BASE_URL ?? "http://127.0.0.1:8080").trim();
const outDir = (process.env.E2E_OUT_DIR ?? "/tmp/harness-e2e-logs/latest").trim();

export default defineConfig({
  testDir: ".",
  testMatch: "**/*.spec.ts",
  outputDir: `${outDir}/test-results`,
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 30_000,
  expect: {
    timeout: 15_000,
  },
  reporter: [
    ["list"],
    ["json", { outputFile: `${outDir}/playwright-report.json` }],
  ],
  use: {
    baseURL,
    viewport: { width: 1440, height: 900 },
    ignoreHTTPSErrors: true,
    actionTimeout: 15_000,
    navigationTimeout: 15_000,
  },
});
