"""
async client for the sf-voice media api.
the public contract matches client.SfVoiceMedia, with awaitable methods.
"""

from __future__ import annotations

import asyncio
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


class AsyncSfVoiceMedia:
    """async client for the sf-voice media api."""

    def __init__(
        self,
        *,
        base_url: str,
        api_key: str,
        timeout_ms: int = 30_000,
        transport: Optional[httpx.AsyncBaseTransport] = None,
    ) -> None:
        """create a configured async sf-voice media client."""
        self._base_url = base_url.rstrip("/")
        self._timeout_ms = timeout_ms
        self._client = httpx.AsyncClient(
            base_url=self._base_url,
            headers={"X-API-Key": api_key},
            timeout=timeout_ms / 1000,
            transport=transport,
        )

    async def _request(self, method: str, path: str, **kwargs: Any) -> Any:
        """send one request and decode the response body."""
        try:
            response = await self._client.request(method, path, **kwargs)
        except httpx.TimeoutException as exc:
            raise SfVoiceMediaRequestTimeoutError(self._timeout_ms) from exc

        return decode_response(response)

    async def ingest(self, request: IngestRequest) -> IngestResponse:
        """submit media for ingestion from a url, s3 key, or file upload."""
        if request["source"] == "file":
            data, files = build_file_ingest_payload(request)
            body = await self._request("POST", "/v1/ingest", data=data, files=files)
        else:
            body = await self._request("POST", "/v1/ingest", json=compact_dict(request))

        return IngestResponse.from_dict(body)

    async def get_task(self, task_id: str) -> Task:
        """fetch the current state of an ingestion task."""
        body = await self._request("GET", f"/v1/tasks/{path_segment(task_id)}")
        return Task.from_dict(body)

    async def poll_task(
        self,
        task_id: str,
        options: Optional[PollTaskOptions] = None,
    ) -> Task:
        """poll get_task until the task reaches ready or failed."""
        options = options or {}
        interval_ms = options.get("interval_ms", 1500)
        timeout_ms = options.get("timeout_ms", 120_000)
        deadline = time.monotonic() + (timeout_ms / 1000)

        while True:
            task = await self.get_task(task_id)
            if task.is_terminal:
                return task

            remaining_s = deadline - time.monotonic()
            if remaining_s <= 0:
                raise SfVoiceMediaPollTimeoutError(task_id, timeout_ms)

            sleep_s = min(interval_ms / 1000, remaining_s)
            await asyncio.sleep(sleep_s)

    async def list_assets(
        self,
        params: Optional[ListAssetsParams] = None,
    ) -> AssetListResponse:
        """list all assets in the library, paginated."""
        body = await self._request("GET", "/v1/assets", params=compact_dict(params or {}))
        return AssetListResponse.from_dict(body)

    async def get_asset(self, asset_id: str) -> Asset:
        """fetch one asset by asset_id."""
        body = await self._request("GET", f"/v1/assets/{path_segment(asset_id)}")
        return Asset.from_dict(body)

    async def delete_asset(self, asset_id: str) -> None:
        """soft-delete an asset."""
        await self._request("DELETE", f"/v1/assets/{path_segment(asset_id)}")

    async def search(self, request: SearchRequest) -> SearchResponse:
        """run semantic search across indexed media."""
        body = await self._request("POST", "/v1/search", json=compact_dict(request))
        return SearchResponse.from_dict(body)

    async def close(self) -> None:
        """close the underlying http session."""
        await self._client.aclose()

    async def __aenter__(self) -> "AsyncSfVoiceMedia":
        """enter an async context manager and return this client."""
        return self

    async def __aexit__(self, *_: Any) -> None:
        """close the client when leaving an async context manager."""
        await self.close()
