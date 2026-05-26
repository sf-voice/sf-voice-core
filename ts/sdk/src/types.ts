/**
 * all public types for the @sf-voice/media SDK.
 * mirrors the shapes returned by the sf-voice media API.
 */

// ─── shared ──────────────────────────────────────────────────────────────────

export type MediaType = "video" | "audio";
export type SourceType = "url" | "s3";
export type TaskStatus = "pending" | "indexing" | "ready" | "failed";
export type SearchMatchType = "visual" | "conversation" | "text_in_video";

export type MediaMetadata = {
  title?: string;
  tags?: string[];
};

/** a single asset in the library */
export type Asset = {
  id: string;
  media_type: MediaType;
  source_type: SourceType;
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

export type IngestRequest =
  | {
      source: "url";
      url: string;
      media_type?: MediaType;
      metadata?: MediaMetadata;
    }
  | {
      source: "s3";
      s3_key: string;
      media_type?: MediaType;
      metadata?: MediaMetadata;
    };

export type IngestResponse = {
  asset_id: string;
  task_id: string;
  status: "pending";
};

// ─── tasks ───────────────────────────────────────────────────────────────────

export type Task = {
  task_id: string;
  asset_id: string;
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
  types?: SearchMatchType[];
  asset_ids?: string[];
  /** 0.0–1.0, default 0.5 */
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
  match_type: SearchMatchType;
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
