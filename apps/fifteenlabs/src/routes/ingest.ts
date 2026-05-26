import type { FastifyInstance } from "fastify";
import { SfVoiceMedia } from "@sf-voice/media";
import { config } from "../config.js";

export async function ingestRoutes(app: FastifyInstance) {
  const client = new SfVoiceMedia({
    baseUrl: config.sfVoice.baseUrl,
    apiKey: config.sfVoice.apiKey,
  });

  // submit a URL for ingest — returns immediately with asset_id + task_id
  app.post<{ Body: { url: string; media_type?: "video" | "audio" } }>(
    "/ingest",
    {
      schema: {
        body: {
          type: "object",
          required: ["url"],
          properties: {
            url: { type: "string" },
            media_type: { type: "string", enum: ["video", "audio"] },
          },
        },
      },
    },
    async (req, reply) => {
      const resp = await client.ingest({
        source: "url",
        url: req.body.url,
        media_type: req.body.media_type,
      });
      reply.code(202).send(resp);
    }
  );

  // poll the status of a task
  app.get<{ Params: { id: string } }>("/task/:id", async (req, reply) => {
    const task = await client.getTask(req.params.id);
    reply.send(task);
  });
}
