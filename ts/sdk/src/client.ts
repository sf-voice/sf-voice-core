import {
   SfVoiceMediaError,
   SfVoiceMediaPollTimeoutError,
   SfVoiceMediaRequestTimeoutError,
} from "./errors.js";
import type {
   ApiErrorBody,
   Document,
   DocumentListResponse,
   IngestRequest,
   IngestResponse,
   Job,
   ListDocumentsParams,
   PollJobOptions,
   SearchRequest,
   SearchResponse,
} from "./types.js";

/** sleep utility used by pollJob */
const sleep = (ms: number): Promise<void> =>
   new Promise((resolve) => setTimeout(resolve, ms));

/**
 * build a url query string from an object by encoding defined values.
 * properties with `undefined` are omitted.
 */
function toQueryString(
   params: Record<string, string | number | boolean | undefined>,
): string {
   const entries = Object.entries(params).filter(
      ([, v]) => v !== undefined,
   ) as [string, string | number | boolean][];
   if (entries.length === 0) return "";
   return (
      "?" +
      new URLSearchParams(
         entries.map(([k, v]) => [k, String(v)] as [string, string]),
      )
   );
}

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
 *
 * const { document_id, job_id } = await client.ingest({
 *   source: "url",
 *   project: "my-project",
 *   url: "https://example.com/clip.mp4",
 * });
 *
 * const job = await client.pollJob(job_id);
 * console.log(job.status); // "done" | "failed"
 * ```
 */
export class SfVoiceMedia {
   private readonly baseUrl: string;
   private readonly headers: Record<string, string>;
   private readonly timeoutMs: number;

   constructor({ baseUrl, apiKey, timeoutMs = 30_000 }: SfVoiceMediaOptions) {
      this.baseUrl = baseUrl.replace(/\/$/, "");
      this.headers = { "X-API-Key": apiKey };
      this.timeoutMs = timeoutMs;
   }

   // ─── internal request helper ───────────────────────────────────────────────

   private async request<T>(
      method: string,
      path: string,
      body?: unknown,
      headers: Record<string, string> = {},
   ): Promise<T> {
      const url = `${this.baseUrl}${path}`;
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), this.timeoutMs);
      const init: RequestInit = {
         method,
         headers: { ...this.headers, ...headers },
         signal: controller.signal,
      };

      if (body !== undefined) {
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

      if (res.status === 204) {
         return null as T;
      }

      let json: unknown;
      try {
         json = await res.json();
      } catch {
         throw new SfVoiceMediaError(
            "provider_unavailable",
            `unexpected non-JSON response from server (HTTP ${res.status})`,
            res.status,
         );
      }

      if (!res.ok) {
         const errBody = json as ApiErrorBody;
         throw new SfVoiceMediaError(
            errBody?.error?.code ?? "provider_unavailable",
            errBody?.error?.message ??
               `request failed with status ${res.status}`,
            res.status,
         );
      }

      return json as T;
   }

   // ─── public methods ────────────────────────────────────────────────────────

   /**
    * submit a media URL or s3 key for ingestion under a project. returns
    * immediately with a job_id you can poll with `getJob` or `pollJob`.
    *
    * file uploads (Blob / Buffer) are not yet supported on this client —
    * route is coming in a follow-up release.
    */
   async ingest(req: IngestRequest): Promise<IngestResponse> {
      return this.request<IngestResponse>("POST", "/v1/ingest", req);
   }

   /** fetch the current state of an ingest job. */
   async getJob(jobId: string): Promise<Job> {
      return this.request<Job>("GET", `/v1/tasks/${encodeURIComponent(jobId)}`);
   }

   /** list documents in the org, optionally filtered to a project. */
   async listDocuments(
      params: ListDocumentsParams = {},
   ): Promise<DocumentListResponse> {
      const qs = toQueryString(params);
      return this.request<DocumentListResponse>("GET", `/v1/videos${qs}`);
   }

   /** fetch a single document by id. */
   async getDocument(documentId: string): Promise<Document> {
      return this.request<Document>(
         "GET",
         `/v1/videos/${encodeURIComponent(documentId)}`,
      );
   }

   /** delete a document. resolves void on success (HTTP 204). */
   async deleteDocument(documentId: string): Promise<void> {
      return this.request<void>(
         "DELETE",
         `/v1/videos/${encodeURIComponent(documentId)}`,
      );
   }

   /** run a text search across the project's transcripts. */
   async search(req: SearchRequest): Promise<SearchResponse> {
      return this.request<SearchResponse>("POST", "/v1/search", req);
   }

   /**
    * polls `getJob` until the job reaches a terminal state
    * (`"done"` | `"failed"` | `"cancelled"`), then returns the final Job.
    *
    * throws `SfVoiceMediaPollTimeoutError` if `timeoutMs` is exceeded.
    */
   async pollJob(
      jobId: string,
      { intervalMs = 1500, timeoutMs = 120_000 }: PollJobOptions = {},
   ): Promise<Job> {
      const deadline = Date.now() + timeoutMs;

      while (true) {
         const job = await this.getJob(jobId);

         if (
            job.status === "done" ||
            job.status === "failed" ||
            job.status === "cancelled"
         ) {
            return job;
         }

         if (Date.now() + intervalMs > deadline) {
            throw new SfVoiceMediaPollTimeoutError(jobId, timeoutMs);
         }

         await sleep(intervalMs);
      }
   }
}
