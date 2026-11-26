import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  // The examples import the package by name, as an app would; here that's the source.
  resolve: { alias: { "audience-kit": fileURLToPath(new URL("./src/index.ts", import.meta.url)) } },
  test: {
    include: ["test/**/*.test.ts"],
    coverage: {
      provider: "v8",
      include: ["src/**/*.ts"],
      reporter: ["text", "lcov"],
      // CI fails under the repository's floor (85% on Swift and Kotlin, PR #49).
      thresholds: { lines: 85, statements: 85, functions: 85, branches: 80 },
    },
  },
});
