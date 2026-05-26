//! `SfVoiceMedia` — the main async client for the sf-voice media API.
//!
//! construct once, reuse across tasks. the underlying `reqwest::Client`
//! connection pool is shared, so cloning is cheap.

use std::time::Duration;

use reqwest::{header, Client, StatusCode};
use tokio::time::Instant;

use crate::{
    error::SfVoiceMediaError,
    types::{
        Asset, AssetListResponse, IngestRequest, IngestResponse, SearchRequest, SearchResponse,
        Task,
    },
};

/// async client for the sf-voice media API.
///
/// ```no_run
/// # use sf_voice::SfVoiceMedia;
/// let client = SfVoiceMedia::new("https://api.sf-voice.com", "your-api-key");
/// ```
#[derive(Clone, Debug)]
pub struct SfVoiceMedia {
    base_url: String,
    http: Client,
}

impl SfVoiceMedia {
    /// construct a client.
    ///
    /// `base_url` should not have a trailing slash.
    /// `api_key` is sent as `X-API-Key` on every request.
    pub fn new(base_url: impl Into<String>, api_key: impl Into<String>) -> Self {
        let mut auth_value =
            header::HeaderValue::from_str(&api_key.into()).expect("api key must be a valid header value");
        auth_value.set_sensitive(true);

        let mut default_headers = header::HeaderMap::new();
        default_headers.insert("X-API-Key", auth_value);

        let http = Client::builder()
            .default_headers(default_headers)
            .build()
            .expect("failed to build http client");

        Self {
            base_url: base_url.into(),
            http,
        }
    }

    // ─── internal helpers ─────────────────────────────────────────────────────

    fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url, path)
    }

    /// map any non-2xx reqwest response into `SfVoiceMediaError::Api`.
    async fn check(response: reqwest::Response) -> Result<reqwest::Response, SfVoiceMediaError> {
        if response.status().is_success() {
            return Ok(response);
        }
        let status = response.status().as_u16();
        let body = response.bytes().await.unwrap_or_default();
        Err(SfVoiceMediaError::from_response(status, &body))
    }

    // ─── public API ───────────────────────────────────────────────────────────

    /// submit a media source for ingestion.
    ///
    /// returns immediately with a `task_id` you can poll via `get_task` or
    /// `poll_task`. the HTTP response is 202 Accepted.
    pub async fn ingest(&self, request: &IngestRequest) -> Result<IngestResponse, SfVoiceMediaError> {
        let response = self
            .http
            .post(self.url("/v1/ingest"))
            .json(request)
            .send()
            .await?;

        Ok(Self::check(response).await?.json().await?)
    }

    /// fetch the current state of an ingest task.
    pub async fn get_task(&self, task_id: impl Into<String>) -> Result<Task, SfVoiceMediaError> {
        let response = self
            .http
            .get(self.url(&format!("/v1/tasks/{}", task_id.into())))
            .send()
            .await?;

        Ok(Self::check(response).await?.json().await?)
    }

    /// poll `get_task` repeatedly until the task reaches a terminal state
    /// (`ready` or `failed`), or until `timeout` elapses.
    ///
    /// `interval` — how long to wait between polls.
    /// `timeout`  — max total wall time before returning `PollTimeout`.
    pub async fn poll_task(
        &self,
        task_id: impl Into<String>,
        interval: Duration,
        timeout: Duration,
    ) -> Result<Task, SfVoiceMediaError> {
        let task_id = task_id.into();
        let deadline = Instant::now() + timeout;

        loop {
            let task = self.get_task(&task_id).await?;
            if task.status.is_terminal() {
                return Ok(task);
            }
            if Instant::now() >= deadline {
                return Err(SfVoiceMediaError::PollTimeout {
                    task_id: task_id.clone(),
                });
            }
            tokio::time::sleep(interval).await;
        }
    }

    /// list all assets, paginated.
    ///
    /// pass `None` for `page` / `limit` to use server defaults.
    pub async fn list_assets(
        &self,
        page: Option<u32>,
        limit: Option<u32>,
    ) -> Result<AssetListResponse, SfVoiceMediaError> {
        let mut request = self.http.get(self.url("/v1/assets"));

        if let Some(p) = page {
            request = request.query(&[("page", p)]);
        }
        if let Some(l) = limit {
            request = request.query(&[("limit", l)]);
        }

        let response = request.send().await?;
        Ok(Self::check(response).await?.json().await?)
    }

    /// fetch a single asset by ID.
    pub async fn get_asset(&self, id: impl Into<String>) -> Result<Asset, SfVoiceMediaError> {
        let response = self
            .http
            .get(self.url(&format!("/v1/assets/{}", id.into())))
            .send()
            .await?;

        Ok(Self::check(response).await?.json().await?)
    }

    /// soft-delete an asset by ID. the backend retains the record but excludes
    /// it from list results. the API returns 204 No Content on success.
    pub async fn delete_asset(&self, id: impl Into<String>) -> Result<(), SfVoiceMediaError> {
        let response = self
            .http
            .delete(self.url(&format!("/v1/assets/{}", id.into())))
            .send()
            .await?;

        // 204 has no body — check status directly rather than trying to parse json
        let status = response.status();
        if status == StatusCode::NO_CONTENT {
            return Ok(());
        }
        let status_u16 = status.as_u16();
        let body = response.bytes().await.unwrap_or_default();
        Err(SfVoiceMediaError::from_response(status_u16, &body))
    }

    /// run a semantic search across ingested media.
    pub async fn search(
        &self,
        request: &SearchRequest,
    ) -> Result<SearchResponse, SfVoiceMediaError> {
        let response = self
            .http
            .post(self.url("/v1/search"))
            .json(request)
            .send()
            .await?;

        Ok(Self::check(response).await?.json().await?)
    }
}
