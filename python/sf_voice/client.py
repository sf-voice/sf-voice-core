"""
sync client for the sf-voice media api.
create one client and reuse it across requests.
"""

from __future__ import annotations

import time
from typing import Any, Optional

import httpx

from ._wire import (
    build_file_ingest_payload,
    compact_dict,
    decode_response,
    path_segment,
)
from .errors import SfVoiceMediaPollTimeoutError, SfVoiceMediaRequestTimeoutError
from .models import (
    Asset,
    AssetListResponse,
    IngestRequest,
    IngestResponse,
    ListAssetsParams,
    PollTaskOptions,
    SearchRequest,
    SearchResponse,
    Task,
)


class SfVoiceMedia:
    """synchronous client for the sf-voice media api."""

    def __init__(
        self,
        *,
        base_url: str,
        api_key: str,
        timeout_ms: int = 30_000,
        transport: Optional[httpx.BaseTransport] = None,
    ) -> None:
        """create a configured sf-voice media client."""
        self._base_url = base_url.rstrip("/")
        self._timeout_ms = timeout_ms
        self._client = httpx.Client(
            base_url=self._base_url,
            headers={"X-API-Key": api_key},
            timeout=timeout_ms / 1000,
            transport=transport,
        )

    def _request(self, method: str, path: str, **kwargs: Any) -> Any:
        """send one request and decode the response body."""
        try:
            response = self._client.request(method, path, **kwargs)
        except httpx.TimeoutException as exc:
            raise SfVoiceMediaRequestTimeoutError(self._timeout_ms) from exc

        return decode_response(response)

    def ingest(self, request: IngestRequest) -> IngestResponse:
        """submit media for ingestion from a url, s3 key, or file upload."""
        if request["source"] == "file":
            data, files = build_file_ingest_payload(request)
            body = self._request("POST", "/v1/ingest", data=data, files=files)
        else:
            body = self._request("POST", "/v1/ingest", json=compact_dict(request))

        return IngestResponse.from_dict(body)

    def get_task(self, task_id: str) -> Task:
        """fetch the current state of an ingestion task."""
        body = self._request("GET", f"/v1/tasks/{path_segment(task_id)}")
        return Task.from_dict(body)

    def poll_task(self, task_id: str, options: Optional[PollTaskOptions] = None) -> Task:
        """poll get_task until the task reaches ready or failed."""
        options = options or {}
        interval_ms = options.get("interval_ms", 1500)
        timeout_ms = options.get("timeout_ms", 120_000)
        deadline = time.monotonic() + (timeout_ms / 1000)

        while True:
            task = self.get_task(task_id)
            if task.is_terminal:
                return task

            remaining_s = deadline - time.monotonic()
            if remaining_s <= 0:
                raise SfVoiceMediaPollTimeoutError(task_id, timeout_ms)

            sleep_s = min(interval_ms / 1000, remaining_s)
            time.sleep(sleep_s)

    def list_assets(
        self,
        params: Optional[ListAssetsParams] = None,
    ) -> AssetListResponse:
        """list all assets in the library, paginated."""
        body = self._request("GET", "/v1/assets", params=compact_dict(params or {}))
        return AssetListResponse.from_dict(body)

    def get_asset(self, asset_id: str) -> Asset:
        """fetch one asset by asset_id."""
        body = self._request("GET", f"/v1/assets/{path_segment(asset_id)}")
        return Asset.from_dict(body)

    def delete_asset(self, asset_id: str) -> None:
        """soft-delete an asset."""
        self._request("DELETE", f"/v1/assets/{path_segment(asset_id)}")

    def search(self, request: SearchRequest) -> SearchResponse:
        """run semantic search across indexed media."""
        body = self._request("POST", "/v1/search", json=compact_dict(request))
        return SearchResponse.from_dict(body)

    def close(self) -> None:
        """close the underlying http session."""
        self._client.close()

    def __enter__(self) -> "SfVoiceMedia":
        """enter a context manager and return this client."""
        return self

    def __exit__(self, *_: Any) -> None:
        """close the client when leaving a context manager."""
        self.close()
