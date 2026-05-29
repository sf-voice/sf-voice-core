//! public types that mirror the v1 API wire shapes. serde uses
//! snake_case throughout — same as the API — so no per-field renames.

use serde::{Deserialize, Serialize};

// ─── enums ───────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaKind {
    Video,
    Audio,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SourceKind {
    Url,
    S3,
}

/// async job state. `Done`, `Failed`, and `Cancelled` are terminal.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum JobStatus {
    Queued,
    Running,
    Done,
    Failed,
    Cancelled,
}

impl JobStatus {
    /// true when no further state change is expected.
    pub fn is_terminal(&self) -> bool {
        matches!(self, JobStatus::Done | JobStatus::Failed | JobStatus::Cancelled)
    }
}

/// per-document processing state, separate from the job that drives it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DocumentStatus {
    Queued,
    Downloading,
    Extracting,
    Uploading,
    Ready,
    Failed,
}

/// match-type returned by search. v1 only has transcript matches.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SearchMatchType {
    Conversation,
}

// ─── shared ──────────────────────────────────────────────────────────────────

/// opaque caller metadata, persisted on the document at ingest time.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Metadata {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PageInfo {
    pub total: u64,
    pub page: u32,
    pub limit: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_page_token: Option<String>,
}

// ─── document ────────────────────────────────────────────────────────────────

/// a single ingested document in the org. fields mirror the
/// `documents` table columns the v1 routes expose.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Document {
    pub id: String,
    pub media_kind: MediaKind,
    pub source_kind: SourceKind,
    pub source_url: Option<String>,
    pub status: DocumentStatus,
    pub duration_ms: Option<i32>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DocumentListResponse {
    pub items: Vec<Document>,
    pub page_info: PageInfo,
}

// ─── ingest ──────────────────────────────────────────────────────────────────

/// request body for `POST /v1/ingest`. use `IngestRequest::from_url`
/// or `IngestRequest::from_s3`, then `.project()` + optional setters.
/// `project` is required — leaving it unset is a server-side 400.
#[derive(Debug, Clone, Serialize)]
pub struct IngestRequest {
    pub source: SourceKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub s3_key: Option<String>,
    /// project slug under the authenticated org. required.
    pub project: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub media_type: Option<MediaKind>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata: Option<Metadata>,
}

impl IngestRequest {
    pub fn from_url(url: impl Into<String>) -> Self {
        Self {
            source: SourceKind::Url,
            url: Some(url.into()),
            s3_key: None,
            project: String::new(),
            media_type: None,
            metadata: None,
        }
    }

    pub fn from_s3(s3_key: impl Into<String>) -> Self {
        Self {
            source: SourceKind::S3,
            url: None,
            s3_key: Some(s3_key.into()),
            project: String::new(),
            media_type: None,
            metadata: None,
        }
    }

    /// REQUIRED — set the project slug under the authenticated org.
    pub fn project(mut self, project: impl Into<String>) -> Self {
        self.project = project.into();
        self
    }

    pub fn media_type(mut self, media_type: MediaKind) -> Self {
        self.media_type = Some(media_type);
        self
    }

    pub fn metadata(mut self, metadata: Metadata) -> Self {
        self.metadata = Some(metadata);
        self
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IngestResponse {
    pub document_id: String,
    pub job_id: String,
    /// always "queued" at ingest time.
    pub status: String,
}

// ─── jobs (formerly tasks) ───────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Job {
    pub job_id: String,
    pub document_id: Option<String>,
    pub status: JobStatus,
    pub error: Option<String>,
    pub created_at: String,
    pub completed_at: Option<String>,
}

// ─── search ──────────────────────────────────────────────────────────────────

/// request body for `POST /v1/search`. `project` is required.
#[derive(Debug, Clone, Serialize)]
pub struct SearchRequest {
    pub query: String,
    pub project: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub document_ids: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub page: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<u32>,
}

impl SearchRequest {
    /// build a search request. `project` is required and is passed here.
    pub fn new(query: impl Into<String>, project: impl Into<String>) -> Self {
        Self {
            query: query.into(),
            project: project.into(),
            document_ids: None,
            page: None,
            limit: None,
        }
    }

    pub fn document_ids(mut self, ids: Vec<impl Into<String>>) -> Self {
        self.document_ids = Some(ids.into_iter().map(Into::into).collect());
        self
    }

    pub fn page(mut self, page: u32) -> Self {
        self.page = Some(page);
        self
    }

    pub fn limit(mut self, limit: u32) -> Self {
        self.limit = Some(limit);
        self
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    pub document_id: String,
    pub score: f32,
    pub start_ms: i32,
    pub end_ms: i32,
    pub text: String,
    pub match_type: SearchMatchType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResponse {
    pub results: Vec<SearchResult>,
    pub page_info: PageInfo,
}
