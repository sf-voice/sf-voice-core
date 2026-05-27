import {
  SfVoiceMediaError,
  SfVoiceMediaPollTimeoutError,
  SfVoiceMediaRequestTimeoutError,
} from "./errors.js";
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

/**
 * Build a URL query string from an object by encoding defined values.
 *
 * @param params - Object whose string/number/boolean values will be URL-encoded; properties with `undefined` are omitted
 * @returns A query string beginning with `?` containing the encoded key/value pairs, or an empty string if no defined parameters exist
 */
function toQueryString(
  params: Record<string, string | number | boolean | undefined>
): string {
  const entries = Object.entries(params).filter(
    ([, v]) => v !== undefined
  ) as [string, string | number | boolean][];
  if (entries.length === 0) return "";
  return "?" + new URLSearchParams(entries.map(([k, v]) => [k, String(v)] as [string, string]));
}

function toUploadBlob(
  file: Blob | ArrayBuffer | Uint8Array,
  contentType?: string
): Blob {
  if (file instanceof Blob) return file;

  const bytes =
    file instanceof ArrayBuffer
      ? file
      : (() => {
          const copy = new Uint8Array(file.byteLength);
          copy.set(file);
          return copy.buffer;
        })();

  return contentType !== undefined
    ? new Blob([bytes], { type: contentType })
    : new Blob([bytes]);
}

// ─── client ──────────────────────────────────────────────────────────────────

export type SfVoiceMediaOptions = {
  /** base URL of the media API, e.g. "https://api.sf-voice.com" */
  baseUrl: string;
  /** API key sent as X-API-Key header */
  apiKey: string;
  /** per-request fetch timeout in ms; defaults to 30 000 */
  timeoutMs?: number;
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
  private readonly timeoutMs: number;

  constructor({ baseUrl, apiKey, timeoutMs = 30_000 }: SfVoiceMediaOptions) {
    // strip trailing slash so every path concat is predictable
    this.baseUrl = baseUrl.replace(/\/$/, "");
    this.headers = {
      "X-API-Key": apiKey,
    };
    this.timeoutMs = timeoutMs;
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
    body?: unknown,
    initBody?: BodyInit,
    headers: Record<string, string> = {}
  ): Promise<T> {
    const url = `${this.baseUrl}${path}`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    const init: RequestInit = {
      method,
      headers: {
        ...this.headers,
        ...headers,
      },
      signal: controller.signal,
    };

    if (initBody !== undefined) {
      init.body = initBody;
    } else if (body !== undefined) {
      init.headers = {
        ...this.headers,
        "Content-Type": "application/json",
        ...headers,
      };
      init.body = JSON.stringify(body);
    }

    let res: Response;
    try {
      res = await fetch(url, init);
    } catch (err) {
      if (err instanceof Error && err.name === "AbortError") {
        throw new SfVoiceMediaRequestTimeoutError(this.timeoutMs);
      }
      throw err;
    } finally {
      clearTimeout(timer);
    }

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
   * submit a media file for ingestion from a URL, S3 key, or file upload.
   * returns immediately with a task_id you can poll with `getTask` or `pollTask`.
   *
   * @example
   * ```ts
   * const { task_id } = await client.ingest({
   *   source: "url",
   *   asset_id: "customer-video-123",
   *   asset_class: "customer_456",
   *   url: "https://example.com/clip.mp4",
   *   metadata: { title: "demo clip" },
   *   types: ["video", "transcript"],
   * });
   * ```
   */
  async ingest(req: IngestRequest): Promise<IngestResponse> {
    if (req.source === "file") {
      const form = new FormData();
      const file = toUploadBlob(req.file, req.content_type);

      form.append("source", req.source);
      form.append("asset_id", req.asset_id);
      form.append("file", file, req.filename);
      if (req.asset_class !== undefined) {
        form.append("asset_class", req.asset_class);
      }
      if (req.media_type !== undefined) form.append("media_type", req.media_type);
      if (req.content_type !== undefined) {
        form.append("content_type", req.content_type);
      }
      if (req.metadata !== undefined) {
        form.append("metadata", JSON.stringify(req.metadata));
      }
      if (req.types !== undefined) form.append("types", JSON.stringify(req.types));

      return this.request<IngestResponse>("POST", "/v1/ingest", undefined, form);
    }

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
   * fetch a single asset by asset_id.
   *
   * @example
   * ```ts
   * const asset = await client.getAsset("customer-video-123");
   * ```
   */
  async getAsset(assetId: string): Promise<Asset> {
    return this.request<Asset>("GET", `/v1/assets/${encodeURIComponent(assetId)}`);
  }

  /**
   * delete an asset. the backend performs a soft delete — the record is
   * retained but excluded from list results.
   * resolves void on success (HTTP 204).
   *
   * @example
   * ```ts
   * await client.deleteAsset("customer-video-123");
   * ```
   */
  async deleteAsset(assetId: string): Promise<void> {
    return this.request<void>("DELETE", `/v1/assets/${encodeURIComponent(assetId)}`);
  }

  /**
   * run a semantic search across indexed media.
   *
   * @example
   * ```ts
   * const { results } = await client.search({
   *   query: "someone mentions the product roadmap",
   *   asset_class: "customer_456",
   *   types: ["transcript"],
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
