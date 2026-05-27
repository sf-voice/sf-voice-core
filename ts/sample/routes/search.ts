import { basename } from "node:path";
import { sfVoice } from "../client.ts";
import { SfVoiceMediaError } from "../../sdk/src/errors.js";
import type { SearchRequest } from "../../sdk/src/types.js";

function apiError(e: unknown): Response {
  if (e instanceof SfVoiceMediaError) {
    return Response.json({ error: e.message, code: e.code }, { status: e.status });
  }
  const msg = e instanceof Error ? e.message : "unknown error";
  return Response.json({ error: msg }, { status: 500 });
}

export const searchRoutes = {
  // POST /api/search  SearchRequest body
  search: async (req: Request): Promise<Response> => {
    const body = await req.json() as SearchRequest;
    if (!body.query?.trim()) {
      return Response.json({ error: "query is required" }, { status: 400 });
    }
    try {
      const results = await sfVoice.search(body);
      return Response.json(results);
    } catch (e) {
      return apiError(e);
    }
  },

  // GET /api/assets?page=&limit=
  list: async (req: Request): Promise<Response> => {
    const { searchParams } = new URL(req.url);
    const page = searchParams.has("page") ? Number(searchParams.get("page")) : undefined;
    const limit = searchParams.has("limit") ? Number(searchParams.get("limit")) : undefined;
    try {
      const assets = await sfVoice.listAssets({ page, limit });
      return Response.json(assets);
    } catch (e) {
      return apiError(e);
    }
  },

  // DELETE /api/assets/:id
  deleteAsset: async (req: Request): Promise<Response> => {
    const id = basename(new URL(req.url).pathname);
    try {
      await sfVoice.deleteAsset(id);
      return new Response(null, { status: 204 });
    } catch (e) {
      return apiError(e);
    }
  },
};
