import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/index.ts"],
  format: ["esm", "cjs"],
  // generate .d.ts for ESM and .d.cts for CJS so both module systems get types
  dts: true,
  sourcemap: true,
  clean: true,
  // no external deps — only stdlib fetch, nothing to bundle out
  splitting: false,
});
