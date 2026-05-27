import { config } from "./config.ts";
import { ingestRoutes } from "./routes/ingest.ts";
import { searchRoutes } from "./routes/search.ts";
// @ts-ignore — bun html import
import index from "./index.html";

const server = Bun.serve({
  port: config.port,
  routes: {
    "/": index,
    "/api/ingest/youtube": { POST: ingestRoutes.youtube },
    "/api/ingest/file":    { POST: ingestRoutes.file },
    "/api/tasks/:id":      { GET: ingestRoutes.task },
    "/media/:filename":    { GET: ingestRoutes.media },
    "/api/search":         { POST: searchRoutes.search },
    "/api/assets":         { GET: searchRoutes.list },
    "/api/assets/:id":     { DELETE: searchRoutes.deleteAsset },
  },
});

console.log(`sf-voice media demo → http://localhost:${server.port}`);
