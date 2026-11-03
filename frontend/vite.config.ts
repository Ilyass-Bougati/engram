import { fileURLToPath } from "node:url";

import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { loadEnv } from "vite";
import { defineConfig } from "vitest/config";

export default defineConfig(({ mode }) => ({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
  },
  server: {
    port: 6969,
    strictPort: true,
    // Same origin in development too: the browser only talks to Vite, which forwards /api.
    // ENGRAM_API_URL picks the backend: set it in .env.local to keep it, or in the environment
    // (which wins) as the end-to-end tests do for their throwaway backend. It's server-only:
    // without a VITE_ prefix it never reaches the browser bundle.
    proxy: {
      "/api":
        loadEnv(mode, import.meta.dirname, "ENGRAM_").ENGRAM_API_URL ?? "http://127.0.0.1:6767",
    },
  },
  test: {
    include: ["src/**/*.test.{ts,tsx}"],
  },
}));
