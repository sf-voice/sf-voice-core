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
        """true when the task has reached a non-progressing state."""
        return self.status in ("ready", "failed")


@dataclass
class IngestResponse:
    asset_id: str
    task_id: str
    status: str  # always "pending" on 202

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "IngestResponse":
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
        return cls(
            items=[Asset.from_dict(i) for i in d.get("items", [])],
            page_info=PageInfo.from_dict(d["page_info"]),
        )
