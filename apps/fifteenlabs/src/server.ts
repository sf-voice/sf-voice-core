import path from "node:path";
import { fileURLToPath } from "node:url";
import fastify from "fastify";
import fastifyStatic from "@fastify/static";
import { ingestRoutes } from "./routes/ingest.js";
import { searchRoutes } from "./routes/search.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/**
 * Creates and configures a Fastify application for the project.
 *
 * Configures logging (level "warn"), serves static files from the repository's `public` directory at `/`, and registers the ingest and search route groups.
 *
 * @returns The configured Fastify instance ready to be started.
 */
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
