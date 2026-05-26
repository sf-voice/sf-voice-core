//! all public types that mirror the sf-voice media API's wire shapes.
//! serde rename_all = "snake_case" is used throughout since the API
//! returns snake_case JSON and Rust convention is snake_case anyway,
//! so no per-field renames are needed.

use serde::{Deserialize, Serialize};

// ─── enums ───────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaType {
    Video,
    Audio,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SourceType {
    Url,
    S3,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    Pending,
    Indexing,
    Ready,
    Failed,
}

impl TaskStatus {
    /// returns true when the task has reached a non-progressing state.
    pub fn is_terminal(&self) -> bool {
        matches!(self, TaskStatus::Ready | TaskStatus::Failed)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SearchType {
    Visual,
    Conversation,
    TextInVideo,
}

// ─── shared ──────────────────────────────────────────────────────────────────

/// optional metadata attached to an asset at ingest time.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MediaMetadata {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
}

/// pagination envelope returned by list and search endpoints.
#[derive(Debug, Clone, Deserialize)]
pub struct PageInfo {
    pub total: u64,
    pub page: u32,
    pub limit: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_page_token: Option<String>,
}

// ─── assets ──────────────────────────────────────────────────────────────────

/// a single asset in the library.
#[derive(Debug, Clone, Deserialize)]
pub struct Asset {
    pub id: String,
    pub media_type: MediaType,
    pub source_type: SourceType,
    pub status: TaskStatus,
    pub metadata: Option<MediaMetadata>,
    pub duration_ms: Option<u64>,
    pub created_at: String,
    pub updated_at: String,
}

/// response envelope for `GET /v1/assets`.
#[derive(Debug, Clone, Deserialize)]
pub struct AssetListResponse {
    pub items: Vec<Asset>,
    pub page_info: PageInfo,
}

// ─── ingest ──────────────────────────────────────────────────────────────────

/// source-specific body for `POST /v1/ingest`.
/// use `IngestRequest::from_url` or `IngestRequest::from_s3` then chain
/// `.media_type()` / `.metadata()` to fill optional fields.
#[derive(Debug, Clone, Serialize)]
pub struct IngestRequest {
    pub source: SourceType,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub s3_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub media_type: Option<MediaType>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata: Option<MediaMetadata>,
}

impl IngestRequest {
    /// ingest from a public or pre-signed URL.
    pub fn from_url(url: impl Into<String>) -> Self {
        Self {
            source: SourceType::Url,
            url: Some(url.into()),
            s3_key: None,
            media_type: None,
            metadata: None,
        }
    }

    /// ingest from an S3 object key (bucket is server-configured).
    pub fn from_s3(s3_key: impl Into<String>) -> Self {
        Self {
            source: SourceType::S3,
            url: None,
            s3_key: Some(s3_key.into()),
            media_type: None,
            metadata: None,
        }
    }

    /// hint the server about whether the source is video or audio.
    pub fn media_type(mut self, media_type: MediaType) -> Self {
        self.media_type = Some(media_type);
        self
    }

    /// attach optional title / tag metadata.
    pub fn metadata(mut self, metadata: MediaMetadata) -> Self {
        self.metadata = Some(metadata);
        self
    }
}

/// response body for a successful `POST /v1/ingest` (HTTP 202).
#[derive(Debug, Clone, Deserialize)]
pub struct IngestResponse {
    pub asset_id: String,
    pub task_id: String,
    /// always "pending" at ingest time.
    pub status: String,
}

// ─── tasks ───────────────────────────────────────────────────────────────────

/// response body for `GET /v1/tasks/:task_id`.
#[derive(Debug, Clone, Deserialize)]
pub struct Task {
    pub task_id: String,
    pub asset_id: String,
    pub status: TaskStatus,
    pub error: Option<String>,
    pub created_at: String,
    pub completed_at: Option<String>,
}

// ─── search ──────────────────────────────────────────────────────────────────

/// request body for `POST /v1/search`.
/// use `SearchRequest::new(query)` then chain optional setters.
#[derive(Debug, Clone, Serialize)]
pub struct SearchRequest {
    pub query: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub types: Option<Vec<SearchType>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub asset_ids: Option<Vec<String>>,
    /// similarity threshold between 0.0 and 1.0. defaults to 0.5 server-side.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub threshold: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub page: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<u32>,
}

impl SearchRequest {
    /// create a minimal search request with just the query string.
    pub fn new(query: impl Into<String>) -> Self {
        Self {
            query: query.into(),
            types: None,
            asset_ids: None,
            threshold: None,
            page: None,
            limit: None,
        }
    }

    /// restrict which match modalities are searched.
    pub fn types(mut self, types: Vec<SearchType>) -> Self {
        self.types = Some(types);
        self
    }

    /// restrict search to a specific set of asset IDs.
    pub fn asset_ids(mut self, ids: Vec<impl Into<String>>) -> Self {
        self.asset_ids = Some(ids.into_iter().map(Into::into).collect());
        self
    }

    /// similarity threshold between 0.0 and 1.0.
    pub fn threshold(mut self, threshold: f32) -> Self {
        self.threshold = Some(threshold);
        self
    }

    /// page number (1-based).
    pub fn page(mut self, page: u32) -> Self {
        self.page = Some(page);
        self
    }

    /// number of results per page.
    pub fn limit(mut self, limit: u32) -> Self {
        self.limit = Some(limit);
        self
    }
}

/// a single search hit.
#[derive(Debug, Clone, Deserialize)]
pub struct SearchResult {
    pub asset_id: String,
    /// similarity score, higher is better.
    pub score: f32,
    /// start of the matching segment in milliseconds.
    pub start_ms: u64,
    /// end of the matching segment in milliseconds.
    pub end_ms: u64,
    pub match_type: SearchType,
    pub thumbnail_url: Option<String>,
}

/// response body for `POST /v1/search`.
#[derive(Debug, Clone, Deserialize)]
pub struct SearchResponse {
    pub results: Vec<SearchResult>,
    pub page_info: PageInfo,
}
