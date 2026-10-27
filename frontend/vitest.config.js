import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import path from "path";

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  test: {
    environment: "jsdom",
    // An http origin makes jsdom expose real Web Storage (localStorage /
    // sessionStorage) instead of an inert stub.
    environmentOptions: {
      jsdom: { url: "http://localhost:5173/" },
    },
    globals: true,
    setupFiles: ["./src/test/setup.js"],
    include: ["src/**/*.test.{js,jsx}"],
    // Bounded: a hung test fails fast instead of stalling the suite.
    testTimeout: 10000,
    hookTimeout: 10000,
  },
});
