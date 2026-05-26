import type { FastifyInstance } from "fastify";
import type { SearchMatchType } from "@sf-voice/media";
import { SfVoiceMedia } from "@sf-voice/media";
import { config } from "../config.js";

export async function searchRoutes(app: FastifyInstance) {
  const client = new SfVoiceMedia({
    baseUrl: config.sfVoice.baseUrl,
    apiKey: config.sfVoice.apiKey,
  });

  // semantic search across all indexed media
  app.post<{
    Body: {
      query: string;
      types?: SearchMatchType[];
      asset_ids?: string[];
      threshold?: number;
    };
  }>(
    "/search",
    {
      schema: {
        body: {
          type: "object",
          required: ["query"],
          properties: {
            query: { type: "string" },
            types: { type: "array", items: { type: "string" } },
            asset_ids: { type: "array", items: { type: "string" } },
            threshold: { type: "number", minimum: 0, maximum: 1 },
          },
        },
      },
    },
    async (req, reply) => {
      const resp = await client.search(req.body);
      reply.send(resp);
    }
  );

  // list all assets
  app.get<{ Querystring: { page?: number; limit?: number } }>(
    "/assets",
    async (req, reply) => {
      const resp = await client.listAssets({
        page: req.query.page,
        limit: req.query.limit,
      });
      reply.send(resp);
    }
  );
}
