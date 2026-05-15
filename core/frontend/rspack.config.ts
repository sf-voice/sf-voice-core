import { defineConfig } from "@rspack/cli";
import { HtmlRspackPlugin } from "@rspack/core";
import path from "node:path";
import { RsdoctorRspackPlugin } from "@rsdoctor/rspack-plugin";

export default defineConfig({
   entry: { main: "./src/index.tsx" },
   // without this, the dev server has no HTML to serve at `/` and falls
   // back to its built-in placeholder page (the one with the strict
   // default-src 'none' CSP, hence the chrome devtools probe error).
   // HtmlRspackPlugin reads our index.html, injects the compiled bundle
   // automatically, and serves it at `/`.
   plugins: [
      new HtmlRspackPlugin({
         template: "./index.html",
      }),
      process.env.RSDOCTOR &&
         new RsdoctorRspackPlugin({
            // plugin options
         }),
   ],
   devServer: {
      port: 3000,
      historyApiFallback: true,
      hot: true,
   },
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

   experiments: { css: true },
});
