"""
sync client for the sf-voice media API.
uses httpx under the hood; instantiate once and reuse across requests.
"""

from __future__ import annotations

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


class SfVoiceMedia:
    """synchronous client for the sf-voice media API.

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
        Create a configured SfVoiceMedia synchronous client for the sf-voice API.
        
        Parameters:
            api_key (str): API key sent in the `X-API-Key` header for authenticated requests.
            base_url (str): Base URL for API requests; trailing slashes are removed. Defaults to "https://api.sf-voice.com".
            timeout (float): Per-request timeout in seconds. Defaults to 30.0.
        """
        self._base_url = base_url.rstrip("/")
        self._client = httpx.Client(
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

    def _get(self, path: str, params: Optional[Dict[str, Any]] = None) -> Any:
        """
        Fetch JSON from the client's API at the specified relative path.
        
        Parameters:
            path (str): API path relative to the client's base_url (for example, "/v1/assets").
            params (Optional[Dict[str, Any]]): Optional query parameters to include in the request; keys and values should be JSON-serializable.
        
        Returns:
            Any: Parsed JSON response (typically a dict or list) derived from the HTTP response body.
        """
        response = self._client.get(path, params=params)
        self._raise_for_status(response)
        return response.json()

    def _post(self, path: str, json: Dict[str, Any]) -> Any:
        """
        Send a POST request to the given path with the provided JSON body and return the parsed response.
        
        Parameters:
        	path (str): Request path relative to the client's base URL.
        	json (Dict[str, Any]): JSON-serializable request body.
        
        Returns:
        	Any: Parsed JSON response body, or `None` if the server responded with HTTP 204 No Content.
        
        Raises:
        	SfVoiceMediaError: If the HTTP response status is not successful (non-2xx) — propagated from internal error handling.
        """
        response = self._client.post(path, json=json)
        self._raise_for_status(response)
        # 204 No Content has no body
        if response.status_code == 204:
            return None
        return response.json()

    def _delete(self, path: str) -> None:
        """
        Send a DELETE request to the specified API path.
        
        Parameters:
            path (str): Request path relative to the client's base_url (for example, "/v1/assets/{asset_id}").
        
        Raises:
            SfVoiceMediaError: If the HTTP response status is not successful.
        """
        response = self._client.delete(path)
        self._raise_for_status(response)

    # ------------------------------------------------------------------ #
    # public API                                                           #
    # ------------------------------------------------------------------ #

    def ingest(
        self,
        source: str,
        url: Optional[str] = None,
        s3_key: Optional[str] = None,
        media_type: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> IngestResponse:
        """
        Submit a new media item for ingestion.
        
        Parameters:
            source (str): Source type, either "url" or "s3".
            url (Optional[str]): Public URL of the media file; required when source is "url".
            s3_key (Optional[str]): S3 object key; required when source is "s3".
            media_type (Optional[str]): "video" or "audio". If omitted, the server will infer the type.
            metadata (Optional[Dict[str, Any]]): Arbitrary key/value pairs stored with the asset.
        
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
        data = self._post("/v1/ingest", body)
        return IngestResponse.from_dict(data)

    def get_task(self, task_id: str) -> Task:
        """
        Retrieve the current state of an ingestion task.
        
        Parameters:
            task_id (str): The ID of the task to retrieve (for example, the ID returned by ingest()).
        
        Returns:
            Task: The task resource with its current status and metadata.
        """
        data = self._get(f"/v1/tasks/{task_id}")
        return Task.from_dict(data)

    def list_assets(self, page: int = 1, limit: int = 20) -> AssetListResponse:
        """
        Retrieve a paginated list of assets.
        
        Parameters:
            page (int): 1-indexed page number to fetch.
            limit (int): Number of items per page, maximum 50.
        
        Returns:
            AssetListResponse: Parsed list of assets and pagination metadata.
        """
        data = self._get("/v1/assets", params={"page": page, "limit": limit})
        return AssetListResponse.from_dict(data)

    def get_asset(self, asset_id: str) -> Asset:
        """
        Retrieve an asset by its identifier.
        
        Returns:
            Asset: The asset corresponding to the provided `asset_id`.
        
        Raises:
            SfVoiceMediaError: If the API responds with a non-success status.
        """
        data = self._get(f"/v1/assets/{asset_id}")
        return Asset.from_dict(data)

    def delete_asset(self, asset_id: str) -> None:
        """
        Soft-delete an asset so the backend retains the record but excludes it from results.
        
        Parameters:
            asset_id (str): Identifier of the asset to soft-delete.
        """
        self._delete(f"/v1/assets/{asset_id}")

    def search(
        self,
        query: str,
        types: Optional[List[str]] = None,
        asset_ids: Optional[List[str]] = None,
        threshold: float = 0.5,
        page: int = 1,
        limit: int = 20,
    ) -> SearchResponse:
        """
        Search ingested media using a natural-language semantic query.
        
        Parameters:
            query (str): Natural-language query string.
            types (Optional[List[str]]): Optional subset of ["visual", "conversation", "text_in_video"] to restrict result types; when omitted searches all types.
            asset_ids (Optional[List[str]]): Optional list of asset IDs to restrict the search; when omitted searches across all assets.
            threshold (float): Minimum similarity score between 0 and 1 to include a result.
            page (int): 1-indexed page number for paginated results.
            limit (int): Number of results per page (maximum 50).
        
        Returns:
            SearchResponse: Matching search results and pagination metadata.
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
        data = self._post("/v1/search", body)
        return SearchResponse.from_dict(data)

    def poll_task(
        self,
        task_id: str,
        interval_s: float = 2.0,
        timeout_s: float = 300.0,
    ) -> Task:
        """
        Waits until the specified task reaches a terminal state.
        
        Polls the task status periodically until it becomes terminal or the timeout elapses.
        
        Parameters:
            task_id (str): ID of the task to poll.
            interval_s (float): Seconds between polling attempts.
            timeout_s (float): Maximum total wait time in seconds.
        
        Returns:
            Task: The terminal Task object.
        
        Raises:
            TimeoutError: If the task is still non-terminal after timeout_s seconds.
            SfVoiceMediaError: If an API request fails while polling.
        """
        deadline = time.monotonic() + timeout_s
        while True:
            task = self.get_task(task_id)
            if task.is_terminal:
                return task
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(
                    f"task {task_id!r} did not complete within {timeout_s}s "
                    f"(last status: {task.status!r})"
                )
            # sleep at most what's left so we don't overshoot the deadline
            time.sleep(min(interval_s, remaining))

    def close(self) -> None:
        """
        Close the underlying HTTP session.
        
        Closes the internal httpx.Client used by the client. Safe to call multiple times.
        """
        self._client.close()

    def __enter__(self) -> "SfVoiceMedia":
        """
        Enter a context manager and return the client instance.
        
        Returns:
            self: The SfVoiceMedia client instance.
        """
        return self

    def __exit__(self, *_: Any) -> None:
        """
        Close the client's underlying HTTP session when exiting a context.
        
        This invokes self.close(), which closes the internal httpx.Client. It is safe to call even if the client is already closed.
        """
        self.close()
