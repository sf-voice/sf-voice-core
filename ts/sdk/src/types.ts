/**
 * public types for the @sf-voice/media SDK. mirrors the wire shapes
 * the v1 API returns after the documents/project rewrite.
 *
 * vocabulary:
 *   document — a single ingested asset (audio or video). previously
 *              called "asset" / "video" interchangeably; we've collapsed
 *              to the canonical name now that the backend table is
 *              `documents`.
 *   project  — required workspace grouping under an org. slugs are
 *              human handles like "sf-voice-f30b0c/marketing-clips".
 *   job      — async work unit tracking an ingest. previously "task".
 */

// ─── shared ──────────────────────────────────────────────────────────────────

export type MediaKind = "video" | "audio";
export type SourceKind = "url" | "s3";
export type JobStatus =
  | "queued"
  | "running"
  | "done"
  | "failed"
  | "cancelled";
export type DocumentStatus =
  | "queued"
  | "downloading"
  | "extracting"
  | "uploading"
  | "ready"
  | "failed";

export type Metadata = Record<string, string | number | boolean>;

// ─── document ────────────────────────────────────────────────────────────────

export type Document = {
  id: string;
  media_kind: MediaKind;
  source_kind: SourceKind;
  source_url?: string;
  status: DocumentStatus;
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
  /** project slug under the authenticated org. required. */
  project: string;
  /** "video" or "audio". server detects from extension when omitted. */
  media_kind?: MediaKind;
  /** opaque caller metadata, persisted on the document. */
  metadata?: Metadata;
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
  );

export type IngestResponse = {
  document_id: string;
  job_id: string;
  status: "queued";
};

// ─── jobs (formerly "tasks") ─────────────────────────────────────────────────

export type Job = {
  job_id: string;
  document_id?: string;
  status: JobStatus;
  error?: string;
  created_at: string;
  completed_at?: string;
};

// ─── document listing ────────────────────────────────────────────────────────

export type ListDocumentsParams = {
  /** optional project slug filter. omit to list all documents in the org. */
  project?: string;
  page?: number;
  /** max 50 */
  limit?: number;
};

export type DocumentListResponse = {
  items: Document[];
  page_info: PageInfo;
};

// ─── search ──────────────────────────────────────────────────────────────────

export type SearchMatchType = "conversation";

export type SearchRequest = {
  query: string;
  /** project slug under the authenticated org. required. */
  project: string;
  /** narrow to specific documents. */
  document_ids?: string[];
  page?: number;
  /** max 50 */
  limit?: number;
};

export type SearchResult = {
  document_id: string;
  score: number;
  start_ms: number;
  end_ms: number;
  text: string;
  match_type: SearchMatchType;
};

export type SearchResponse = {
  results: SearchResult[];
  page_info: PageInfo;
};

// ─── poll ────────────────────────────────────────────────────────────────────

export type PollJobOptions = {
  /** how long to wait between polls, in ms. default 1500 */
  intervalMs?: number;
  /** max total wait time in ms. default 120_000 (2 min) */
  timeoutMs?: number;
};

// ─── error ───────────────────────────────────────────────────────────────────

export type ApiErrorCode =
  | "bucket_not_connected"
  | "s3_access_denied"
  | "s3_key_not_found"
  | "unsupported_format"
  | "file_too_large"
  | "provider_unavailable"
  | "unauthorized"
  | "not_found"
  | "missing_field"
  | "invalid_source"
  | "invalid_media_type"
  | "invalid_url"
  | "rate_limited"
  | (string & {});

export type ApiErrorBody = {
  error: {
    code: ApiErrorCode;
    message: string;
  };
};
