import { SfVoiceMediaError, SfVoiceMediaPollTimeoutError } from "./errors.js";
import type {
  ApiErrorBody,
  Asset,
  AssetListResponse,
  IngestRequest,
  IngestResponse,
  ListAssetsParams,
  PollTaskOptions,
  SearchRequest,
  SearchResponse,
  Task,
} from "./types.js";

// ─── helpers ─────────────────────────────────────────────────────────────────

/** sleep utility used by pollTask */
const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

/** build a query-string from a plain object, omitting undefined values */
function toQueryString(
  params: Record<string, string | number | boolean | undefined>
): string {
  const entries = Object.entries(params).filter(
    ([, v]) => v !== undefined
  ) as [string, string | number | boolean][];
  if (entries.length === 0) return "";
  return "?" + new URLSearchParams(entries.map(([k, v]) => [k, String(v)]));
}

// ─── client ──────────────────────────────────────────────────────────────────

export type SfVoiceMediaOptions = {
  /** base URL of the media API, e.g. "https://api.sf-voice.com" */
  baseUrl: string;
  /** API key sent as X-API-Key header */
  apiKey: string;
};

/**
 * SDK client for the sf-voice media API.
 *
 * @example
 * ```ts
 * const client = new SfVoiceMedia({
 *   baseUrl: "https://api.sf-voice.com",
 *   apiKey: process.env.SF_VOICE_API_KEY!,
 * });
 * ```
 */
export class SfVoiceMedia {
  private readonly baseUrl: string;
  private readonly headers: Record<string, string>;

  constructor({ baseUrl, apiKey }: SfVoiceMediaOptions) {
    // strip trailing slash so every path concat is predictable
    this.baseUrl = baseUrl.replace(/\/$/, "");
    this.headers = {
      "Content-Type": "application/json",
      "X-API-Key": apiKey,
    };
  }

  // ─── internal request helper ───────────────────────────────────────────────

  /**
   * executes a fetch and unwraps the JSON body.
   * throws SfVoiceMediaError on any non-2xx status.
   *
   * returns `null` for 204 No Content responses.
   */
  private async request<T>(
    method: string,
    path: string,
    body?: unknown
  ): Promise<T> {
    const url = `${this.baseUrl}${path}`;
    const init: RequestInit = {
      method,
      headers: this.headers,
    };
    if (body !== undefined) {
      init.body = JSON.stringify(body);
    }

    const res = await fetch(url, init);

    // 204 — no body to parse
    if (res.status === 204) {
      return null as T;
    }

    // attempt to parse JSON regardless of status so we get the error payload
    let json: unknown;
    try {
      json = await res.json();
    } catch {
      // non-JSON body on an error status
      throw new SfVoiceMediaError(
        "provider_unavailable",
        `unexpected non-JSON response from server (HTTP ${res.status})`,
        res.status
      );
    }

    if (!res.ok) {
      const errBody = json as ApiErrorBody;
      throw new SfVoiceMediaError(
        errBody?.error?.code ?? "provider_unavailable",
        errBody?.error?.message ?? `request failed with status ${res.status}`,
        res.status
      );
    }

    return json as T;
  }

  // ─── public methods ────────────────────────────────────────────────────────

  /**
   * submit a media file for ingestion from a URL or S3 key.
   * returns immediately with a task_id you can poll with `getTask` or `pollTask`.
   *
   * @example
   * ```ts
   * const { task_id } = await client.ingest({
   *   source: "url",
   *   url: "https://example.com/clip.mp4",
   *   metadata: { title: "Demo clip" },
   * });
   * ```
   */
  async ingest(req: IngestRequest): Promise<IngestResponse> {
    return this.request<IngestResponse>("POST", "/v1/ingest", req);
  }

  /**
   * fetch the current state of an ingestion task.
   *
   * @example
   * ```ts
   * const task = await client.getTask("task_abc123");
   * console.log(task.status); // "pending" | "indexing" | "ready" | "failed"
   * ```
   */
  async getTask(taskId: string): Promise<Task> {
    return this.request<Task>("GET", `/v1/tasks/${encodeURIComponent(taskId)}`);
  }

  /**
   * list all assets in the library, paginated.
   *
   * @example
   * ```ts
   * const { items, page_info } = await client.listAssets({ page: 1, limit: 20 });
   * ```
   */
  async listAssets(params: ListAssetsParams = {}): Promise<AssetListResponse> {
    const qs = toQueryString(params);
    return this.request<AssetListResponse>("GET", `/v1/assets${qs}`);
  }

  /**
   * fetch a single asset by id.
   *
   * @example
   * ```ts
   * const asset = await client.getAsset("ast_abc123");
   * ```
   */
  async getAsset(id: string): Promise<Asset> {
    return this.request<Asset>("GET", `/v1/assets/${encodeURIComponent(id)}`);
  }

  /**
   * delete an asset. the backend performs a soft delete — the record is
   * retained but excluded from list results.
   * resolves void on success (HTTP 204).
   *
   * @example
   * ```ts
   * await client.deleteAsset("ast_abc123");
   * ```
   */
  async deleteAsset(id: string): Promise<void> {
    return this.request<void>("DELETE", `/v1/assets/${encodeURIComponent(id)}`);
  }

  /**
   * run a semantic search across indexed media.
   *
   * @example
   * ```ts
   * const { results } = await client.search({
   *   query: "someone mentions the product roadmap",
   *   types: ["conversation"],
   *   threshold: 0.7,
   * });
   * ```
   */
  async search(req: SearchRequest): Promise<SearchResponse> {
    return this.request<SearchResponse>("POST", "/v1/search", req);
  }

  /**
   * polls `getTask` at a fixed interval until the task reaches
   * `"ready"` or `"failed"`, then returns the final Task object.
   *
   * throws `SfVoiceMediaPollTimeoutError` if `timeoutMs` is exceeded
   * before a terminal state is reached.
   *
   * @example
   * ```ts
   * const { task_id } = await client.ingest({ source: "url", url: "..." });
   * const task = await client.pollTask(task_id, { intervalMs: 2000, timeoutMs: 60_000 });
   * if (task.status === "failed") throw new Error(task.error);
   * console.log("ready:", task.asset_id);
   * ```
   */
  async pollTask(
    taskId: string,
    { intervalMs = 1500, timeoutMs = 120_000 }: PollTaskOptions = {}
  ): Promise<Task> {
    const deadline = Date.now() + timeoutMs;

    while (true) {
      const task = await this.getTask(taskId);

      if (task.status === "ready" || task.status === "failed") {
        return task;
      }

      if (Date.now() + intervalMs > deadline) {
        throw new SfVoiceMediaPollTimeoutError(taskId, timeoutMs);
      }

      await sleep(intervalMs);
    }
  }
}
