import { defineConfig } from "@rspack/cli";
import path from "node:path";

// rspack is the bundler (drop-in webpack replacement, rust-backed). this
// config covers dev server + production build. tailwind v4 plugs in via
// postcss-loader; no tailwind.config.js needed — config lives in index.css.
export default defineConfig({
  entry: { main: "./src/index.tsx" },
  output: {
    path: path.resolve(__dirname, "dist"),
    filename: "[name].[contenthash:8].js",
    publicPath: "/",
    clean: true,
  },
  resolve: {
    extensions: [".tsx", ".ts", ".jsx", ".js"],
    alias: {
      "@": path.resolve(__dirname, "src"),
    },
  },
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        use: {
          loader: "builtin:swc-loader",
          options: {
            jsc: {
              parser: { syntax: "typescript", tsx: true },
              transform: { react: { runtime: "automatic" } },
            },
          },
        },
      },
      {
        test: /\.css$/,
        type: "css",
        use: ["postcss-loader"],
      },
    ],
  },
  devServer: {
    port: 5173,
    historyApiFallback: true,
    hot: true,
  },
  experiments: { css: true },
});
