/**
 * all public types for the @sf-voice/media SDK.
 * mirrors the shapes returned by the sf-voice media API.
 */

// ─── shared ──────────────────────────────────────────────────────────────────

export type MediaType = "video" | "audio";
export type SourceType = "url" | "s3" | "file";
export type TaskStatus = "pending" | "indexing" | "ready" | "failed";
export type MediaSearchType = "video" | "audio" | "transcript";

export type MediaMetadata = Record<string, string | number | boolean>;
export type IngestFile = Blob | ArrayBuffer | Uint8Array;

/** a single asset in the library */
export type Asset = {
  asset_id: string;
  asset_class?: string;
  media_type: MediaType;
  source_type: SourceType;
  types: MediaSearchType[];
  status: TaskStatus;
  metadata?: MediaMetadata;
  duration_ms?: number;
  created_at: string;
  updated_at: string;
};

// ─── pagination ──────────────────────────────────────────────────────────────

export type PageInfo = {
  total: number;
  page: number;
  limit: number;
  next_page_token?: string;
};

// ─── ingest ──────────────────────────────────────────────────────────────────

export type IngestBase = {
  /** customer-provided unique id for correlating this asset */
  asset_id: string;
  /** logical group for this asset. the backend maps this to a provider index. */
  asset_class?: string;
  media_type?: MediaType;
  metadata?: MediaMetadata;
  types?: MediaSearchType[];
};

export type IngestRequest = IngestBase &
  (
    | {
        source: "url";
        url: string;
      }
    | {
        source: "s3";
        s3_key: string;
      }
    | {
        source: "file";
        file: IngestFile;
        filename: string;
        content_type?: string;
      }
  );

export type IngestResponse = {
  asset_id: string;
  task_id: string;
  status: "pending";
};

// ─── tasks ───────────────────────────────────────────────────────────────────

export type Task = {
  task_id: string;
  asset_id: string;
  asset_class?: string;
  types: MediaSearchType[];
  status: TaskStatus;
  error?: string;
  created_at: string;
  completed_at?: string;
};

// ─── assets ──────────────────────────────────────────────────────────────────

export type ListAssetsParams = {
  page?: number;
  /** max 50 */
  limit?: number;
};

export type AssetListResponse = {
  items: Asset[];
  page_info: PageInfo;
};

// ─── search ──────────────────────────────────────────────────────────────────

export type SearchRequest = {
  query: string;
  types?: MediaSearchType[];
  asset_ids?: string[];
  asset_class?: string;
  /** set this to "all" to intentionally search every asset. */
  scope?: "all";
  /** minimum match score from 0.0 to 1.0. higher values return fewer, more confident results. default 0.5. */
  threshold?: number;
  page?: number;
  /** max 50 */
  limit?: number;
};

export type SearchResult = {
  asset_id: string;
  score: number;
  start_ms: number;
  end_ms: number;
  match_type: MediaSearchType;
  thumbnail_url?: string;
};

export type SearchResponse = {
  results: SearchResult[];
  page_info: PageInfo;
};

// ─── poll ────────────────────────────────────────────────────────────────────

export type PollTaskOptions = {
  /** how long to wait between polls, in ms. default 1500 */
  intervalMs?: number;
  /** max total wait time in ms. default 120_000 (2 min) */
  timeoutMs?: number;
};

// ─── error ───────────────────────────────────────────────────────────────────

/** all known API error codes */
export type ApiErrorCode =
  | "bucket_not_connected"
  | "s3_access_denied"
  | "s3_key_not_found"
  | "unsupported_format"
  | "file_too_large"
  | "provider_unavailable"
  | "unauthorized"
  | "not_found"
  | "rate_limited"
  // catch-all for future codes the server may return
  | (string & {});

export type ApiErrorBody = {
  error: {
    code: ApiErrorCode;
    message: string;
  };
};
