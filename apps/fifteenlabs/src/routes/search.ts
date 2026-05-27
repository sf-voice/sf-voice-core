import type { FastifyInstance } from "fastify";
import type { SearchMatchType } from "@sf-voice/media";
import { SfVoiceMedia } from "@sf-voice/media";
import { config } from "../config.js";

/**
 * Registers HTTP routes for media search and asset listing on the given Fastify instance.
 *
 * - POST /search: accepts a search payload (requires `query`, optional `types`, `asset_ids`, `threshold`) and forwards it to the SfVoiceMedia search API, returning the API response.
 * - GET /assets: accepts optional `page` and `limit` query parameters and returns the SfVoiceMedia assets list.
 */
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
      page?: number;
      limit?: number;
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
            types: {
              type: "array",
              items: {
                type: "string",
                enum: ["visual", "conversation", "text_in_video"],
              },
            },
            asset_ids: { type: "array", items: { type: "string" } },
            threshold: { type: "number", minimum: 0, maximum: 1 },
            page: { type: "integer", minimum: 1 },
            limit: { type: "integer", minimum: 1 },
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
    {
      schema: {
        querystring: {
          type: "object",
          properties: {
            page: { type: "integer", minimum: 1 },
            limit: { type: "integer", minimum: 1 },
          },
        },
      },
    },
    async (req, reply) => {
      const resp = await client.listAssets({
        page: req.query.page,
        limit: req.query.limit,
      });
      reply.send(resp);
    }
  );
}
