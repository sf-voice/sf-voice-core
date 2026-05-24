// Fastify HTTP + WebSocket server for the prototype.
//   * POST /telnyx/webhook         — call-control webhooks
//   * GET  /telnyx/media-streaming — bidirectional WS for audio
//   * GET  /health                 — liveness

import Fastify from "fastify";
import fastifyWebsocket from "@fastify/websocket";
import type { WebSocket } from "ws";
import { config } from "./config.ts";
import { log } from "./log.ts";
import { handle as handleWebhook } from "./telnyx/webhook.ts";
import { attach as attachBridge } from "./media/bridge.ts";

export async function buildServer() {
  const app = Fastify({ logger: false, bodyLimit: 5 * 1024 * 1024 });
  await app.register(fastifyWebsocket);

  app.get("/health", async () => ({ ok: true }));

  app.post("/telnyx/webhook", async (req, reply) => {
    await handleWebhook(req.body as Parameters<typeof handleWebhook>[0]);
    reply.code(200).send("");
  });

  app.get("/telnyx/media-streaming", { websocket: true }, (socket: WebSocket) => {
    log.info("media-streaming: ws connection");
    attachBridge(socket);
  });

  return app;
}

async function main(): Promise<void> {
  const app = await buildServer();
  await app.listen({ port: config.port, host: "0.0.0.0" });
  log.info("fraud-prototype listening", {
    port: config.port,
    publicUrl: config.publicUrl,
  });
}

main().catch((err: Error) => {
  log.error("server boot failed", { err: err.message, stack: err.stack });
  process.exit(1);
});
