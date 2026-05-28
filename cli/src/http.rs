//! thin reqwest wrapper for v1 project / org endpoints that the
//! `sf_voice_media` SDK doesn't cover. ingest / search / jobs / docs go
//! through the SDK directly — this module is only the leftover surface.

use anyhow::{anyhow, bail, Result};
use reqwest::header;
use serde::{de::DeserializeOwned, Serialize};

pub struct ApiClient {
    base_url: String,
    http: reqwest::Client,
}

impl ApiClient {
    pub fn new(base_url: &str, api_key: &str) -> Result<Self> {
        let mut headers = header::HeaderMap::new();
        let mut value = header::HeaderValue::from_str(api_key)
            .map_err(|e| anyhow!("invalid api key: {e}"))?;
        value.set_sensitive(true);
        headers.insert("X-API-Key", value);

        let http = reqwest::Client::builder()
            .default_headers(headers)
            .build()?;
        Ok(Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            http,
        })
    }

    pub async fn get<T: DeserializeOwned>(&self, path: &str) -> Result<T> {
        let resp = self.http.get(self.url(path)).send().await?;
        Self::check(resp).await?.json::<T>().await.map_err(Into::into)
    }

    pub async fn post<B: Serialize, T: DeserializeOwned>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<T> {
        let resp = self.http.post(self.url(path)).json(body).send().await?;
        Self::check(resp).await?.json::<T>().await.map_err(Into::into)
    }

    fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url, path)
    }

    async fn check(resp: reqwest::Response) -> Result<reqwest::Response> {
        if resp.status().is_success() {
            return Ok(resp);
        }
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        bail!("api error {status}: {body}");
    }
}
