import { defineConfig, devices } from "@playwright/test";

import { APP_URL } from "./e2e/stack";

export default defineConfig({
  testDir: "e2e",
  // One at a time: the specs share one backend and its per-IP rate limits.
  workers: 1,
  reporter: "list",
  use: { ...devices["Desktop Chrome"], baseURL: APP_URL },
  projects: [
    {
      name: "specimen",
      testMatch: "specimen.spec.ts",
      use: { baseURL: "http://localhost:6969" },
    },
    { name: "stack", testMatch: "stack.setup.ts", teardown: "stack teardown" },
    { name: "stack teardown", testMatch: "stack.teardown.ts" },
    { name: "app", testMatch: "app/*.spec.ts", dependencies: ["stack"] },
    { name: "screens", testMatch: "screens.spec.ts", dependencies: ["stack"] },
  ],
  webServer: [
    {
      command: "npm run dev",
      url: "http://localhost:6969/specimen.html",
      reuseExistingServer: true,
    },
    {
      // Its own dev server, proxying to the throwaway backend that e2e/stack.setup.ts starts.
      command: "npx vite --port 6970 --strictPort",
      url: APP_URL,
      env: { ENGRAM_API_URL: "http://127.0.0.1:6768" },
    },
  ],
});
