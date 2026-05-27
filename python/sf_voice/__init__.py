"""
sf-voice-media Python SDK.

Quick start (sync):

    from sf_voice import SfVoiceMedia

    client = SfVoiceMedia(api_key="your-key", base_url="https://api.sf-voice.com")
    resp = client.ingest(source="url", url="https://example.com/video.mp4")
    task = client.poll_task(resp.task_id)

Quick start (async):

    from sf_voice import AsyncSfVoiceMedia

    async with AsyncSfVoiceMedia(api_key="your-key") as client:
        resp = await client.ingest(source="url", url="https://example.com/video.mp4")
        task = await client.poll_task(resp.task_id)
"""

from .async_client import AsyncSfVoiceMedia
from .client import SfVoiceMedia
from .errors import SfVoiceMediaError
from .models import (
    Asset,
    AssetListResponse,
    IngestResponse,
    PageInfo,
    SearchResponse,
    SearchResult,
    Task,
)

__version__ = "0.1.0"

__all__ = [
    # clients
    "SfVoiceMedia",
    "AsyncSfVoiceMedia",
    # errors
    "SfVoiceMediaError",
    # models
    "Asset",
    "AssetListResponse",
    "IngestResponse",
    "PageInfo",
    "SearchResponse",
    "SearchResult",
    "Task",
]
