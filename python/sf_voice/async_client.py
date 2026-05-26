"""
async client for the sf-voice media API.
identical contract to client.SfVoiceMedia but all methods are async,
backed by httpx.AsyncClient for non-blocking I/O.
"""

from __future__ import annotations

import asyncio
import time
from typing import Any, Dict, List, Optional

import httpx

from .errors import SfVoiceMediaError
from .models import (
    AssetListResponse,
    Asset,
    IngestResponse,
    SearchResponse,
    Task,
)


class AsyncSfVoiceMedia:
    """async client for the sf-voice media API.

    Intended for use with asyncio. Supports async context manager usage:

        async with AsyncSfVoiceMedia(api_key="...") as client:
            result = await client.ingest(source="url", url="https://...")

    Args:
        api_key: your API key — sent as the X-API-Key header on every request.
        base_url: base URL of the API, without a trailing slash.
        timeout: per-request timeout in seconds (default 30).
    """

    def __init__(
        self,
        api_key: str,
        base_url: str = "https://api.sf-voice.com",
        timeout: float = 30.0,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._client = httpx.AsyncClient(
            base_url=self._base_url,
            headers={"X-API-Key": api_key, "Content-Type": "application/json"},
            timeout=timeout,
        )

    # ------------------------------------------------------------------ #
    # internal helpers                                                     #
    # ------------------------------------------------------------------ #

    def _raise_for_status(self, response: httpx.Response) -> None:
        """parse the error envelope and raise SfVoiceMediaError on non-2xx."""
        if response.is_success:
            return
        try:
            body = response.json()
        except Exception:
            body = None
        raise SfVoiceMediaError.from_response(response.status_code, body)

    async def _get(self, path: str, params: Optional[Dict[str, Any]] = None) -> Any:
        response = await self._client.get(path, params=params)
        self._raise_for_status(response)
        return response.json()

    async def _post(self, path: str, json: Dict[str, Any]) -> Any:
        response = await self._client.post(path, json=json)
        self._raise_for_status(response)
        if response.status_code == 204:
            return None
        return response.json()

    async def _delete(self, path: str) -> None:
        response = await self._client.delete(path)
        self._raise_for_status(response)

    # ------------------------------------------------------------------ #
    # public API                                                           #
    # ------------------------------------------------------------------ #

    async def ingest(
        self,
        source: str,
        url: Optional[str] = None,
        s3_key: Optional[str] = None,
        media_type: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> IngestResponse:
        """submit a new media item for ingestion.

        Args:
            source: "url" or "s3".
            url: public URL of the media file (required when source="url").
            s3_key: S3 object key (required when source="s3").
            media_type: "video" or "audio" — inferred by the server when omitted.
            metadata: arbitrary key/value pairs stored alongside the asset.

        Returns:
            IngestResponse with asset_id, task_id, and status="pending".
        """
        body: Dict[str, Any] = {"source": source}
        if url is not None:
            body["url"] = url
        if s3_key is not None:
            body["s3_key"] = s3_key
        if media_type is not None:
            body["media_type"] = media_type
        if metadata is not None:
            body["metadata"] = metadata
        data = await self._post("/v1/ingest", body)
        return IngestResponse.from_dict(data)

    async def get_task(self, task_id: str) -> Task:
        """fetch the current state of an ingestion task.

        Args:
            task_id: the task_id returned by ingest().
        """
        data = await self._get(f"/v1/tasks/{task_id}")
        return Task.from_dict(data)

    async def list_assets(self, page: int = 1, limit: int = 20) -> AssetListResponse:
        """list assets with pagination.

        Args:
            page: 1-indexed page number.
            limit: items per page, max 50.
        """
        data = await self._get("/v1/assets", params={"page": page, "limit": limit})
        return AssetListResponse.from_dict(data)

    async def get_asset(self, asset_id: str) -> Asset:
        """fetch a single asset by id.

        Args:
            asset_id: the id of the asset.
        """
        data = await self._get(f"/v1/assets/{asset_id}")
        return Asset.from_dict(data)

    async def delete_asset(self, asset_id: str) -> None:
        """soft-delete an asset. the backend retains the record but excludes it from results.

        Args:
            asset_id: the id of the asset to delete.
        """
        await self._delete(f"/v1/assets/{asset_id}")

    async def search(
        self,
        query: str,
        types: Optional[List[str]] = None,
        asset_ids: Optional[List[str]] = None,
        threshold: float = 0.5,
        page: int = 1,
        limit: int = 20,
    ) -> SearchResponse:
        """search across ingested media using semantic queries.

        Args:
            query: natural language search query.
            types: subset of ["visual", "conversation", "text_in_video"].
                   defaults to all types when omitted.
            asset_ids: restrict search to these asset ids. searches all when omitted.
            threshold: minimum similarity score, 0–1 (default 0.5).
            page: 1-indexed page number.
            limit: results per page, max 50.
        """
        body: Dict[str, Any] = {
            "query": query,
            "threshold": threshold,
            "page": page,
            "limit": limit,
        }
        if types is not None:
            body["types"] = types
        if asset_ids is not None:
            body["asset_ids"] = asset_ids
        data = await self._post("/v1/search", body)
        return SearchResponse.from_dict(data)

    async def poll_task(
        self,
        task_id: str,
        interval_s: float = 2.0,
        timeout_s: float = 300.0,
    ) -> Task:
        """await until the task reaches a terminal state (ready or failed).

        Polls get_task() every interval_s seconds using asyncio.sleep,
        which yields control back to the event loop between polls.

        Args:
            task_id: the task_id to poll.
            interval_s: seconds between each poll (default 2).
            timeout_s: maximum total wait time in seconds (default 300).

        Returns:
            The terminal Task object.

        Raises:
            TimeoutError: if the task is still non-terminal after timeout_s.
            SfVoiceMediaError: if any API request fails.
        """
        deadline = time.monotonic() + timeout_s
        while True:
            task = await self.get_task(task_id)
            if task.is_terminal:
                return task
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(
                    f"task {task_id!r} did not complete within {timeout_s}s "
                    f"(last status: {task.status!r})"
                )
            await asyncio.sleep(min(interval_s, remaining))

    async def close(self) -> None:
        """close the underlying httpx session. safe to call multiple times."""
        await self._client.aclose()

    async def __aenter__(self) -> "AsyncSfVoiceMedia":
        return self

    async def __aexit__(self, *_: Any) -> None:
        await self.close()
