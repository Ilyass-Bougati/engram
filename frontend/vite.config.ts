import { fileURLToPath } from "node:url";

import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
  },
  server: {
    port: 6969,
    strictPort: true,
    // Same origin in development too: the browser only talks to Vite, which forwards /api.
    proxy: { "/api": "http://127.0.0.1:6767" },
  },
  test: {
    include: ["src/**/*.test.{ts,tsx}"],
  },
});
