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
        """
        Initialize the AsyncSfVoiceMedia client and configure its underlying async HTTP session.
        
        Parameters:
            api_key (str): API key used for the `X-API-Key` request header.
            base_url (str): Base URL for the sf-voice API; trailing slashes are removed.
            timeout (float): Per-request timeout, in seconds, for the underlying HTTP client.
        """
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
        """
        Raise SfVoiceMediaError for non-success HTTP responses.
        
        If the response indicates success, return immediately. Otherwise, attempt to parse the response body as JSON and raise SfVoiceMediaError constructed from the response status code and the parsed body; if JSON parsing fails, use None for the body.
        
        Raises:
            SfVoiceMediaError: when the HTTP response status is not successful, constructed from the response status code and parsed body.
        """
        if response.is_success:
            return
        try:
            body = response.json()
        except Exception:
            body = None
        raise SfVoiceMediaError.from_response(response.status_code, body)

    async def _get(self, path: str, params: Optional[Dict[str, Any]] = None) -> Any:
        """
        Perform an HTTP GET to the given API path and return the parsed JSON body.
        
        Parameters:
            path (str): Request path relative to the client's configured base URL.
            params (Optional[Dict[str, Any]]): Query parameters to include in the request.
        
        Returns:
            Any: The response body decoded from JSON.
        
        Raises:
            SfVoiceMediaError: If the HTTP response status indicates an error.
        """
        response = await self._client.get(path, params=params)
        self._raise_for_status(response)
        return response.json()

    async def _post(self, path: str, json: Dict[str, Any]) -> Any:
        """
        Send a JSON POST request to the given API path and return the parsed response.
        
        Parameters:
            path (str): Request path relative to the client's base URL (e.g., "/v1/ingest").
            json (Dict[str, Any]): JSON-serializable request body to include in the POST.
        
        Returns:
            The parsed JSON response body, or `None` if the server responded with HTTP 204.
        
        Raises:
            SfVoiceMediaError: If the response status is not successful.
        """
        response = await self._client.post(path, json=json)
        self._raise_for_status(response)
        if response.status_code == 204:
            return None
        return response.json()

    async def _delete(self, path: str) -> None:
        """
        Send a DELETE request to the given API path and raise on error.
        
        Parameters:
            path (str): API path relative to the client's base URL (e.g., "/v1/assets/{id}").
        
        Raises:
            SfVoiceMediaError: If the HTTP response has a non-success status code.
        """
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
        """
        Submit a media item for ingestion.
        
        Parameters:
            source (str): Source type, either "url" or "s3".
            url (Optional[str]): Public URL of the media file; required when source is "url".
            s3_key (Optional[str]): S3 object key; required when source is "s3".
            media_type (Optional[str]): Media category, typically "video" or "audio". If omitted, the server will infer it.
            metadata (Optional[Dict[str, Any]]): Arbitrary key/value pairs to store with the asset.
        
        Returns:
            IngestResponse: Contains `asset_id`, `task_id`, and `status` (typically "pending").
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
        """
        Fetch the current state of an ingestion task.
        
        Parameters:
            task_id (str): Identifier of the task as returned by `ingest()`.
        
        Returns:
            Task: The task object representing the task's current state.
        """
        data = await self._get(f"/v1/tasks/{task_id}")
        return Task.from_dict(data)

    async def list_assets(self, page: int = 1, limit: int = 20) -> AssetListResponse:
        """
        Retrieve a paginated list of assets.
        
        Parameters:
            page (int): 1-indexed page number.
            limit (int): Items per page (maximum 50).
        
        Returns:
            AssetListResponse: Paginated assets and pagination metadata for the requested page.
        """
        data = await self._get("/v1/assets", params={"page": page, "limit": limit})
        return AssetListResponse.from_dict(data)

    async def get_asset(self, asset_id: str) -> Asset:
        """
        Fetches an asset by its identifier.
        
        Parameters:
            asset_id (str): The unique identifier of the asset to retrieve.
        
        Returns:
            Asset: The requested asset as an `Asset` instance.
        """
        data = await self._get(f"/v1/assets/{asset_id}")
        return Asset.from_dict(data)

    async def delete_asset(self, asset_id: str) -> None:
        """
        Soft-delete an asset so it is excluded from listings while its record is retained.
        
        Parameters:
            asset_id (str): ID of the asset to delete.
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
        """
        Perform a semantic search over ingested media using a natural language query.
        
        Parameters:
            query (str): Natural language search query.
            types (Optional[List[str]]): Optional subset of media types to search. Allowed values include "visual", "conversation", and "text_in_video". When omitted, all types are searched.
            asset_ids (Optional[List[str]]): Optional list of asset IDs to restrict the search to. When omitted, the search covers all assets.
            threshold (float): Minimum similarity score between 0 and 1 (default 0.5).
            page (int): 1-indexed page number for paginated results (default 1).
            limit (int): Number of results per page, up to 50 (default 20).
        
        Returns:
            SearchResponse: Paginated search results returned by the API.
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
        """
        Waits for a task to reach a terminal state and returns that task.
        
        Parameters:
        	task_id (str): ID of the task to poll.
        	interval_s (float): Seconds between polls.
        	timeout_s (float): Maximum total wait time in seconds.
        
        Returns:
        	Task: The terminal Task object.
        
        Raises:
        	TimeoutError: If the task is still non-terminal after timeout_s (message includes the last observed status).
        	SfVoiceMediaError: If any API request fails.
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
        """
        Close the client's underlying HTTP session and release network resources.
        
        This method is idempotent and safe to call multiple times.
        """
        await self._client.aclose()

    async def __aenter__(self) -> "AsyncSfVoiceMedia":
        """
        Enter an async context and return the client instance.
        
        Returns:
            AsyncSfVoiceMedia: The same client instance for use within the async context.
        """
        return self

    async def __aexit__(self, *_: Any) -> None:
        """
        Exit the asynchronous context by closing the underlying HTTP client.
        
        Closes the client's AsyncClient session. Safe to call multiple times.
        """
        await self.close()
