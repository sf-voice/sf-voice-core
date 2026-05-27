"""
dataclasses for all API response types.
all from_dict methods do lenient parsing: unknown keys are ignored,
missing optional fields fall back to None so forward-compat is preserved.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional


@dataclass
class PageInfo:
    page: int
    limit: int
    total: int
    has_more: bool

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "PageInfo":
        """
        Construct a PageInfo instance from a dictionary containing paging fields.
        
        Parameters:
            d (Dict[str, Any]): Mapping with required keys "page", "limit", "total", and "has_more".
        
        Returns:
            PageInfo: Instance populated from the corresponding values in `d`.
        """
        return cls(
            page=d["page"],
            limit=d["limit"],
            total=d["total"],
            has_more=d["has_more"],
        )


@dataclass
class Asset:
    id: str
    status: str  # "pending" | "indexing" | "ready" | "failed"
    source: str  # "url" | "s3"
    media_type: Optional[str] = None  # "video" | "audio"
    url: Optional[str] = None
    s3_key: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    created_at: Optional[str] = None
    completed_at: Optional[str] = None

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "Asset":
        """
        Create an Asset instance from a dictionary (typically an API response payload).
        
        Parameters:
            d (Dict[str, Any]): Mapping containing asset fields. Required keys: `id`, `status`, `source`. Optional keys: `media_type`, `url`, `s3_key`, `metadata`, `created_at`, `completed_at`. Missing optional fields are set to `None`; `metadata` defaults to an empty dict.
        
        Returns:
            Asset: An Asset populated from the provided mapping.
        """
        return cls(
            id=d["id"],
            status=d["status"],
            source=d["source"],
            media_type=d.get("media_type"),
            url=d.get("url"),
            s3_key=d.get("s3_key"),
            metadata=d.get("metadata") or {},
            created_at=d.get("created_at"),
            completed_at=d.get("completed_at"),
        )


@dataclass
class Task:
    task_id: str
    asset_id: str
    status: str  # "pending" | "indexing" | "ready" | "failed"
    error: Optional[str] = None
    created_at: Optional[str] = None
    completed_at: Optional[str] = None

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "Task":
        """
        Create a Task instance from an API response dictionary.
        
        Parses required keys `task_id`, `asset_id`, and `status` from the input mapping. Optional keys `error`, `created_at`, and `completed_at` are taken if present; unknown keys are ignored and missing optional fields default to None.
        
        Parameters:
            d (Dict[str, Any]): Mapping containing task fields from an API response.
        
        Returns:
            Task: A Task populated from the provided dictionary.
        """
        return cls(
            task_id=d["task_id"],
            asset_id=d["asset_id"],
            status=d["status"],
            error=d.get("error"),
            created_at=d.get("created_at"),
            completed_at=d.get("completed_at"),
        )

    @property
    def is_terminal(self) -> bool:
        """
        Indicates whether the task has reached a terminal state.
        
        Returns:
            True if the task's status is "ready" or "failed", False otherwise.
        """
        return self.status in ("ready", "failed")


@dataclass
class IngestResponse:
    asset_id: str
    task_id: str
    status: str  # always "pending" on 202

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "IngestResponse":
        """
        Create an IngestResponse from a dictionary of API response fields.
        
        Parameters:
            d (Dict[str, Any]): Mapping expected to contain the required keys "asset_id", "task_id", and "status".
        
        Returns:
            IngestResponse: An instance populated from the provided dictionary.
        """
        return cls(
            asset_id=d["asset_id"],
            task_id=d["task_id"],
            status=d["status"],
        )


@dataclass
class SearchResult:
    asset_id: str
    score: float
    start_ms: int
    end_ms: int
    match_type: str  # "visual" | "conversation" | "text_in_video"
    thumbnail_url: Optional[str] = None

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "SearchResult":
        """
        Create a SearchResult from a mapping (typically a parsed JSON object).
        
        Parameters:
            d (Dict[str, Any]): Mapping containing keys "asset_id", "score", "start_ms", "end_ms", and "match_type".
                The optional key "thumbnail_url" may be present. Unknown keys are ignored.
        
        Returns:
            SearchResult: Instance populated from the provided mapping; optional fields are set to None if missing.
        """
        return cls(
            asset_id=d["asset_id"],
            score=d["score"],
            start_ms=d["start_ms"],
            end_ms=d["end_ms"],
            match_type=d["match_type"],
            thumbnail_url=d.get("thumbnail_url"),
        )


@dataclass
class SearchResponse:
    results: List[SearchResult]
    page_info: PageInfo

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "SearchResponse":
        """
        Constructs a SearchResponse from a dictionary representation (typically an API response).
        
        Parameters:
            d (Dict[str, Any]): Dictionary containing "results" (list of result dicts) and "page_info" (page info dict).
        
        Returns:
            SearchResponse: Instance populated from the provided dictionary.
        """
        return cls(
            results=[SearchResult.from_dict(r) for r in d.get("results", [])],
            page_info=PageInfo.from_dict(d["page_info"]),
        )


@dataclass
class AssetListResponse:
    items: List[Asset]
    page_info: PageInfo

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "AssetListResponse":
        """
        Create an AssetListResponse from a dictionary representation of the API response.
        
        Parameters:
            d (Dict[str, Any]): Dictionary containing the asset list payload. Must include a "page_info" mapping; "items" may be omitted or be a list of asset mappings.
        
        Returns:
            AssetListResponse: Instance with `items` parsed into Asset objects and `page_info` parsed into a PageInfo.
        """
        return cls(
            items=[Asset.from_dict(i) for i in d.get("items", [])],
            page_info=PageInfo.from_dict(d["page_info"]),
        )
