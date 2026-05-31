//! `SfVoiceMedia` — async client for the v1 API. construct once, reuse
//! across tasks; the inner `reqwest::Client` connection pool is shared,
//! so cloning is cheap.

use std::time::Duration;

use reqwest::{header, Client, StatusCode};
use tokio::time::Instant;

use crate::{
    error::SfVoiceMediaError,
    types::{
        Document, DocumentListResponse, IngestRequest, IngestResponse, Job, SearchRequest,
        SearchResponse,
    },
};

/// async client for the sf-voice media API.
///
/// ```no_run
/// # use sf_voice_media::SfVoiceMedia;
/// let client = SfVoiceMedia::new("https://api.sf-voice.com", "your-api-key");
/// ```
#[derive(Clone, Debug)]
pub struct SfVoiceMedia {
    base_url: String,
    http: Client,
}

impl SfVoiceMedia {
    /// build a client. `base_url` should not have a trailing slash.
    /// `api_key` is sent as `X-API-Key` and marked sensitive in the
    /// underlying reqwest client.
    pub fn new(base_url: impl Into<String>, api_key: impl Into<String>) -> Self {
        let mut auth_value = header::HeaderValue::from_str(&api_key.into())
            .expect("api key must be a valid header value");
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

    async fn check(response: reqwest::Response) -> Result<reqwest::Response, SfVoiceMediaError> {
        if response.status().is_success() {
            return Ok(response);
        }
        let status = response.status().as_u16();
        let body = response.bytes().await.unwrap_or_default();
        Err(SfVoiceMediaError::from_response(status, &body))
    }

    // ─── public API ───────────────────────────────────────────────────────────

    /// submit a URL or s3 key for ingestion under a project. server
    /// responds 202 with a `job_id` you can poll with `get_job` /
    /// `poll_job`. file/buffer ingest comes in a follow-up release.
    pub async fn ingest(
        &self,
        request: &IngestRequest,
    ) -> Result<IngestResponse, SfVoiceMediaError> {
        let response = self
            .http
            .post(self.url("/v1/ingest"))
            .json(request)
            .send()
            .await?;

        Ok(Self::check(response).await?.json().await?)
    }

    /// fetch the current state of an ingest job.
    pub async fn get_job(&self, job_id: impl Into<String>) -> Result<Job, SfVoiceMediaError> {
        let response = self
            .http
            .get(self.url(&format!("/v1/tasks/{}", job_id.into())))
            .send()
            .await?;

        Ok(Self::check(response).await?.json().await?)
    }

    /// poll `get_job` until the job reaches a terminal state
    /// (`Done` | `Failed` | `Cancelled`) or the timeout elapses.
    pub async fn poll_job(
        &self,
        job_id: impl Into<String>,
        interval: Duration,
        timeout: Duration,
    ) -> Result<Job, SfVoiceMediaError> {
        let job_id = job_id.into();
        let deadline = Instant::now() + timeout;

        loop {
            let job = self.get_job(&job_id).await?;
            if job.status.is_terminal() {
                return Ok(job);
            }
            if Instant::now() >= deadline {
                return Err(SfVoiceMediaError::PollTimeout {
                    job_id: job_id.clone(),
                });
            }
            tokio::time::sleep(interval).await;
        }
    }

    /// list documents in the org, optionally filtered to a project.
    pub async fn list_documents(
        &self,
        project: Option<&str>,
        page: Option<u32>,
        limit: Option<u32>,
    ) -> Result<DocumentListResponse, SfVoiceMediaError> {
        let mut request = self.http.get(self.url("/v1/videos"));
        if let Some(p) = project {
            request = request.query(&[("project", p)]);
        }
        if let Some(p) = page {
            request = request.query(&[("page", p)]);
        }
        if let Some(l) = limit {
            request = request.query(&[("limit", l)]);
        }
        let response = request.send().await?;
        Ok(Self::check(response).await?.json().await?)
    }

    /// fetch a single document by id.
    pub async fn get_document(
        &self,
        id: impl Into<String>,
    ) -> Result<Document, SfVoiceMediaError> {
        let response = self
            .http
            .get(self.url(&format!("/v1/videos/{}", id.into())))
            .send()
            .await?;
        Ok(Self::check(response).await?.json().await?)
    }

    /// delete a document. server responds 204 on success.
    pub async fn delete_document(&self, id: impl Into<String>) -> Result<(), SfVoiceMediaError> {
        let response = self
            .http
            .delete(self.url(&format!("/v1/videos/{}", id.into())))
            .send()
            .await?;

        let status = response.status();
        if status == StatusCode::NO_CONTENT {
            return Ok(());
        }
        let status_u16 = status.as_u16();
        let body = response.bytes().await.unwrap_or_default();
        Err(SfVoiceMediaError::from_response(status_u16, &body))
    }

    /// text search across the project's transcripts.
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
