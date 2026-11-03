import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "e2e",
  fullyParallel: true,
  reporter: "list",
  use: { ...devices["Desktop Chrome"], baseURL: "http://localhost:6969" },
  projects: [{ name: "specimen", testMatch: "specimen.spec.ts" }],
  webServer: {
    command: "npm run dev",
    url: "http://localhost:6969/specimen.html",
    reuseExistingServer: true,
  },
});
