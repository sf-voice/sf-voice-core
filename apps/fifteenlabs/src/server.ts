import path from "node:path";
import { fileURLToPath } from "node:url";
import fastify from "fastify";
import fastifyStatic from "@fastify/static";
import { ingestRoutes } from "./routes/ingest.js";
import { searchRoutes } from "./routes/search.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export async function buildServer() {
  const app = fastify({ logger: { level: "warn" } });

  await app.register(fastifyStatic, {
    root: path.join(__dirname, "../public"),
    prefix: "/",
  });

  await app.register(ingestRoutes, { prefix: "/" });
  await app.register(searchRoutes, { prefix: "/" });

  return app;
}
