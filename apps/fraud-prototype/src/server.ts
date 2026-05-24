// Fastify HTTP + WebSocket server for the prototype.
//   * POST /telnyx/webhook         — call-control webhooks (signed)
//   * GET  /telnyx/media-streaming — bidirectional WS for audio
//   * GET  /health                 — liveness

import Fastify from "fastify";
import type { FastifyRequest } from "fastify";
import fastifyWebsocket from "@fastify/websocket";
import type { WebSocket } from "ws";
import { config } from "./config.ts";
import { log } from "./log.ts";
import { handle as handleWebhook } from "./telnyx/webhook.ts";
import { isVerifyConfigured, verify } from "./telnyx/signature.ts";
import { MEDIA_STREAMING_PATH, WEBHOOK_PATH } from "./telnyx/paths.ts";
import { attach as attachBridge } from "./media/bridge.ts";

// extend FastifyRequest to carry the raw body we capture for signature
// verification.
declare module "fastify" {
  interface FastifyRequest {
    rawBody?: string;
  }
}

export async function buildServer() {
  const app = Fastify({ logger: false, bodyLimit: 5 * 1024 * 1024 });

  // capture raw JSON body so the Telnyx signature verifier can hash
  // exactly what arrived on the wire (Fastify's default JSON parser
  // discards the original string).
  app.addContentTypeParser(
    "application/json",
    { parseAs: "string" },
    (_req, body, done) => {
      try {
        const parsed = body.length === 0 ? {} : JSON.parse(body as string);
        (_req as FastifyRequest).rawBody = body as string;
        done(null, parsed);
      } catch (err) {
        done(err as Error, undefined);
      }
    },
  );

  await app.register(fastifyWebsocket);

  app.get("/health", async () => ({ ok: true }));

  app.post(WEBHOOK_PATH, async (req, reply) => {
    const sigHeader = req.headers["telnyx-signature-ed25519"];
    const tsHeader = req.headers["telnyx-timestamp"];
    const signatureB64 = Array.isArray(sigHeader) ? sigHeader[0] : sigHeader;
    const timestamp = Array.isArray(tsHeader) ? tsHeader[0] : tsHeader;

    const result = await verify({
      signatureB64,
      timestamp,
      rawBody: req.rawBody ?? "",
    });

    if (!result.ok) {
      if (result.reason === "no_key") {
        // dev convenience — accept the request but log loudly. set
        // TELNYX_PUBLIC_KEY for real deployments.
        log.warn("webhook: signature skipped — TELNYX_PUBLIC_KEY not set");
      } else {
        log.warn("webhook: signature rejected", { reason: result.reason });
        reply.code(401).send("");
        return;
      }
    }

    await handleWebhook(req.body as Parameters<typeof handleWebhook>[0]);
    reply.code(200).send("");
  });

  app.get(MEDIA_STREAMING_PATH, { websocket: true }, (socket: WebSocket) => {
    log.info("media-streaming: ws connection");
    attachBridge(socket);
  });

  return app;
}

async function main(): Promise<void> {
  const app = await buildServer();
  if (!isVerifyConfigured()) {
    log.warn(
      "TELNYX_PUBLIC_KEY not set — webhook signatures will NOT be verified. " +
        "Forged requests can trigger outbound calls. Configure for production.",
    );
  }
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
