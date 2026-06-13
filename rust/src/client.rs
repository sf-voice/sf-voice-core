//! `SfVoiceMedia` — the main async client for the sf-voice media API.
//!
//! construct once, reuse across tasks. the underlying `reqwest::Client`
//! connection pool is shared, so cloning is cheap.

use std::collections::HashSet;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use reqwest::{header, Client, StatusCode};
use tokio::time::Instant;

use crate::{
    error::SfVoiceMediaError,
    types::{
        AlertOptions, Asset, AssetListResponse, CreateMonitorRequest, IngestRequest,
        IngestResponse, Monitor, MonitorEvent, MonitorEventListResponse, MonitorListResponse,
        SearchRequest, SearchResponse, Task, UpdateMonitorRequest,
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
    /// Creates a new SfVoiceMedia client configured with a base URL and API key.
    ///
    /// The provided `base_url` should not have a trailing slash. The `api_key` is attached to every request
    /// as the `X-API-Key` header and is marked sensitive in the underlying HTTP client.
    ///
    /// # Examples
    ///
    /// ```
    /// let client = SfVoiceMedia::new("https://api.example.com", "my-secret-key");
    /// ```
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

    /// Concatenates the client's base URL and the provided path into a single String.
    ///
    /// # Examples
    ///
    /// ```
    /// let client = SfVoiceMedia { base_url: "https://api.example.com".to_string(), http: reqwest::Client::new() };
    /// let full = client.url("/v1/ingest");
    /// assert_eq!(full, "https://api.example.com/v1/ingest");
    /// ```
    fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url, path)
    }

    /// Converts a non-success HTTP response into an `SfVoiceMediaError` and otherwise returns the original response.
    ///
    /// If the response status is not in the 2xx range, the function reads the response body (falling back to an empty body on read failure)
    /// and produces an `SfVoiceMediaError` constructed from the numeric status code and response bytes.
    ///
    /// # Returns
    ///
    /// `Ok(response)` when the response status is 2xx, `Err(SfVoiceMediaError::Api { .. })` containing the status and body otherwise.
    async fn check(response: reqwest::Response) -> Result<reqwest::Response, SfVoiceMediaError> {
        if response.status().is_success() {
            return Ok(response);
        }
        let status = response.status().as_u16();
        let body = response.bytes().await.unwrap_or_default();
        Err(SfVoiceMediaError::from_response(status, &body))
    }

    // ─── public API ───────────────────────────────────────────────────────────

    /// Submits a media source for ingestion and returns a task you can track.
    ///
    /// The request is sent to the service's ingest endpoint; the server responds with
    /// 202 Accepted and the returned `IngestResponse` contains the task identifier
    /// that can be retrieved with `get_task` or awaited via `poll_task`.
    ///
    /// # Examples
    ///
    /// ```no_run
    /// #[tokio::main]
    /// async fn main() {
    ///     let client = SfVoiceMedia::new("https://api.example.com", "my-api-key");
    ///     let request = IngestRequest { /* fields */ };
    ///     let response = client.ingest(&request).await.unwrap();
    ///     // response contains a task id to poll for progress
    /// }
    /// ```
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

    /// Fetches the current state of an ingest task.
    ///
    /// On success returns a `Task` parsed from the service's response.
    ///
    /// # Errors
    ///
    /// Returns `SfVoiceMediaError` if the HTTP request fails, the response has a non-success status, or the response body cannot be parsed as a `Task`.
    ///
    /// # Examples
    ///
    /// ```no_run
    /// # async fn run() -> Result<(), Box<dyn std::error::Error>> {
    /// let client = SfVoiceMedia::new("https://api.example.com", "my-api-key");
    /// let task = client.get_task("task-id-123").await?;
    /// println!("task id: {}", task.id);
    /// # Ok(()) }
    /// ```
    pub async fn get_task(&self, task_id: impl Into<String>) -> Result<Task, SfVoiceMediaError> {
        let response = self
            .http
            .get(self.url(&format!("/v1/tasks/{}", task_id.into())))
            .send()
            .await?;

        Ok(Self::check(response).await?.json().await?)
    }

    /// Polls a task until it reaches a terminal state or the timeout elapses.
    ///
    /// Repeatedly fetches the task and returns it once its status is terminal (`ready` or `failed`).
    ///
    /// # Returns
    ///
    /// `Ok(Task)` when the task reaches a terminal state; `Err(SfVoiceMediaError::PollTimeout { task_id })` if the timeout elapses before a terminal state; other `Err(SfVoiceMediaError)` values if fetching the task fails.
    ///
    /// # Examples
    ///
    /// ```no_run
    /// use std::time::Duration;
    ///
    /// # async fn doc_example() -> Result<(), Box<dyn std::error::Error>> {
    /// let client = SfVoiceMedia::new("https://api.example.com", "api-key");
    /// let task = client
    ///     .poll_task("my-task-id", Duration::from_secs(2), Duration::from_secs(60))
    ///     .await?;
    /// println!("final task status: {:?}", task.status);
    /// # Ok(()) }
    /// ```
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

    /// Lists assets with optional pagination.
    ///
    /// If `page` or `limit` is `None`, the server's default values are used. The response
    /// is parsed as an `AssetListResponse` on success; errors are returned as `SfVoiceMediaError`.
    ///
    /// # Examples
    ///
    /// ```no_run
    /// use sf_voice_media::client::SfVoiceMedia;
    ///
    /// // Create the client (example credentials)
    /// let client = SfVoiceMedia::new("https://api.example.com", "api-key");
    ///
    /// // Fetch the first page with up to 50 items
    /// let resp = tokio::runtime::Runtime::new().unwrap().block_on(async {
    ///     client.list_assets(None, Some(50)).await
    /// }).unwrap();
    /// assert!(resp.assets.len() <= 50);
    /// ```
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

    /// Retrieve an asset by its ID.
    ///
    /// On success returns the requested `Asset`. On error returns `SfVoiceMediaError`.
    ///
    /// # Examples
    ///
    /// ```no_run
    /// # use sf_voice_media::SfVoiceMedia;
    /// #[tokio::main]
    /// async fn main() -> Result<(), Box<dyn std::error::Error>> {
    ///     let client = SfVoiceMedia::new("https://api.example.com", "my-api-key");
    ///     let asset = client.get_asset("asset-id").await?;
    ///     println!("{}", asset.id);
    ///     Ok(())
    /// }
    /// ```
    pub async fn get_asset(&self, id: impl Into<String>) -> Result<Asset, SfVoiceMediaError> {
        let response = self
            .http
            .get(self.url(&format!("/v1/assets/{}", id.into())))
            .send()
            .await?;

        Ok(Self::check(response).await?.json().await?)
    }

    /// Soft-delete an asset by its ID.
    ///
    /// Sends a DELETE request to `/v1/assets/{id}`. The backend keeps the record but excludes it from list results.
    /// A successful deletion is indicated by HTTP 204 No Content.
    ///
    /// # Returns
    ///
    /// `Ok(())` if the server returns 204 No Content, `Err(SfVoiceMediaError)` otherwise.
    ///
    /// # Examples
    ///
    /// ```no_run
    /// # async fn run() -> Result<(), SfVoiceMediaError> {
    /// let client = SfVoiceMedia::new("https://api.example.com", "api-key");
    /// client.delete_asset("asset-id").await?;
    /// # Ok(())
    /// # }
    /// ```
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

    /// Perform a semantic search over ingested media and return matching results.
    ///
    /// Sends the provided search request to the service and returns the parsed search response.
    ///
    /// # Examples
    ///
    /// ```no_run
    /// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
    /// let client = SfVoiceMedia::new("https://api.example.com", "API_KEY");
    /// let request = SearchRequest {
    ///     // fill required fields
    ///     ..Default::default()
    /// };
    /// let response = client.search(&request).await?;
    /// // use `response`
    /// # Ok(())
    /// # }
    /// ```
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

    // ─── monitors ────────────────────────────────────────────────────────────

    /// Create a new monitor.
    pub async fn create_monitor(
        &self,
        request: &CreateMonitorRequest,
    ) -> Result<Monitor, SfVoiceMediaError> {
        let response = self
            .http
            .post(self.url("/v1/monitors"))
            .json(request)
            .send()
            .await?;

        Ok(Self::check(response).await?.json().await?)
    }

    /// List all monitors.
    pub async fn list_monitors(&self) -> Result<MonitorListResponse, SfVoiceMediaError> {
        let response = self.http.get(self.url("/v1/monitors")).send().await?;

        Ok(Self::check(response).await?.json().await?)
    }

    /// Fetch a single monitor by ID.
    pub async fn get_monitor(
        &self,
        monitor_id: impl Into<String>,
    ) -> Result<Monitor, SfVoiceMediaError> {
        let response = self
            .http
            .get(self.url(&format!("/v1/monitors/{}", monitor_id.into())))
            .send()
            .await?;

        Ok(Self::check(response).await?.json().await?)
    }

    /// Update a monitor's fields (text, threshold, enabled, asset_class).
    pub async fn update_monitor(
        &self,
        monitor_id: impl Into<String>,
        request: &UpdateMonitorRequest,
    ) -> Result<Monitor, SfVoiceMediaError> {
        let response = self
            .http
            .patch(self.url(&format!("/v1/monitors/{}", monitor_id.into())))
            .json(request)
            .send()
            .await?;

        Ok(Self::check(response).await?.json().await?)
    }

    /// Delete a monitor by ID.
    pub async fn delete_monitor(
        &self,
        monitor_id: impl Into<String>,
    ) -> Result<(), SfVoiceMediaError> {
        let response = self
            .http
            .delete(self.url(&format!("/v1/monitors/{}", monitor_id.into())))
            .send()
            .await?;

        Self::check(response).await?;
        Ok(())
    }

    /// List events for a monitor with optional filtering and pagination.
    pub async fn list_monitor_events(
        &self,
        monitor_id: impl Into<String>,
        matched_only: Option<bool>,
        limit: Option<u64>,
        offset: Option<u64>,
    ) -> Result<MonitorEventListResponse, SfVoiceMediaError> {
        let mut request = self
            .http
            .get(self.url(&format!("/v1/monitors/{}/events", monitor_id.into())));

        if let Some(v) = matched_only {
            request = request.query(&[("matched_only", v.to_string())]);
        }
        if let Some(v) = limit {
            request = request.query(&[("limit", v.to_string())]);
        }
        if let Some(v) = offset {
            request = request.query(&[("offset", v.to_string())]);
        }

        let response = request.send().await?;
        Ok(Self::check(response).await?.json().await?)
    }

    /// High-level convenience: create a monitor, poll for matched events,
    /// invoke the callback for each new match, and clean up on stop.
    ///
    /// Returns an `AlertHandle` whose `stop()` method cancels polling and
    /// deletes the monitor.
    pub async fn alert(
        &self,
        text: &str,
        callback: impl Fn(MonitorEvent) + Send + 'static,
        interval: Duration,
        opts: AlertOptions,
    ) -> Result<AlertHandle, SfVoiceMediaError> {
        let mut req = CreateMonitorRequest::new(text);
        req.slug = opts.slug;
        req.project_id = opts.project_id;
        req.asset_class = opts.asset_class;
        req.threshold = opts.threshold;

        let monitor = self.create_monitor(&req).await?;
        let monitor_id = monitor.id.clone();

        let effective_interval = opts
            .interval_ms
            .map(Duration::from_millis)
            .unwrap_or(interval);

        let stop_flag = Arc::new(AtomicBool::new(false));
        let flag_clone = Arc::clone(&stop_flag);
        let client_clone = self.clone();
        let mid = monitor_id.clone();

        let task = tokio::spawn(async move {
            let mut seen: HashSet<String> = HashSet::new();

            while !flag_clone.load(Ordering::Relaxed) {
                let mut offset = 0u64;
                let limit = 100u64;

                loop {
                    match client_clone
                        .list_monitor_events(&mid, Some(true), Some(limit), Some(offset))
                        .await
                    {
                        Ok(resp) => {
                            let fetched_count = resp.items.len() as u64;
                            for event in resp.items {
                                if seen.insert(event.id.clone()) {
                                    callback(event);
                                }
                            }
                            // Evict old IDs to prevent unbounded memory growth
                            if seen.len() > 10_000 {
                                seen.clear();
                            }
                            // If we got fewer items than the limit, we've exhausted this page cycle
                            if fetched_count < limit {
                                break;
                            }
                            offset += fetched_count;
                        }
                        Err(e) => {
                            eprintln!("error fetching monitor events: {:?}", e);
                            break;
                        }
                    }
                }
                tokio::time::sleep(effective_interval).await;
            }
        });

        Ok(AlertHandle {
            monitor_id,
            stop_flag,
            task,
            client: self.clone(),
        })
    }
}

/// handle returned by `SfVoiceMedia::alert()`. call `stop()` to cancel
/// polling and delete the underlying monitor.
pub struct AlertHandle {
    pub monitor_id: String,
    stop_flag: Arc<AtomicBool>,
    task: tokio::task::JoinHandle<()>,
    client: SfVoiceMedia,
}

impl AlertHandle {
    /// stop polling and delete the monitor. consumes the handle.
    pub async fn stop(self) -> Result<(), SfVoiceMediaError> {
        self.stop_flag.store(true, Ordering::Relaxed);
        let _ = self.task.await;
        self.client.delete_monitor(&self.monitor_id).await?;
        Ok(())
    }
}
