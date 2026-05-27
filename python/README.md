# sf-voice-media

Python SDK for the sf-voice media API.

Version: `0.1.1`

## Installation

```sh
pip install sf-voice-media==0.1.1
```

For local development in this repo:

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
python3 -m compileall -q sf_voice
```

## Usage

### Sync client

```python
import os

from sf_voice import SfVoiceMedia, SfVoiceMediaError

try:
    with SfVoiceMedia(api_key=os.environ["SF_VOICE_API_KEY"]) as client:
        ingest = client.ingest(
            source="url",
            url="https://example.com/recording.mp4",
            media_type="video",
            metadata={"title": "product demo"},
        )

        task = client.poll_task(ingest.task_id, interval_s=2.0, timeout_s=120.0)
        if task.status == "failed":
            raise RuntimeError(task.error or "ingest task failed")

        search = client.search(
            query="product launch",
            asset_ids=[task.asset_id],
            types=["conversation"],
            threshold=0.7,
        )

        print(search.results)
except SfVoiceMediaError as error:
    print(error.code, error.status, error.message)
    raise
```

### Async client

```python
import os

from sf_voice import AsyncSfVoiceMedia

async with AsyncSfVoiceMedia(api_key=os.environ["SF_VOICE_API_KEY"]) as client:
    ingest = await client.ingest(source="url", url="https://example.com/recording.mp4")
    task = await client.poll_task(ingest.task_id)
```

## API

The sync and async clients expose the same API:

- `ingest(...)` - submit URL or S3 media for indexing.
- `get_task(task_id)` - fetch task state.
- `poll_task(task_id, interval_s, timeout_s)` - wait until a task is terminal.
- `list_assets(page, limit)` - list indexed assets.
- `get_asset(asset_id)` - fetch one asset.
- `delete_asset(asset_id)` - soft-delete an asset.
- `search(...)` - search indexed media with natural language.

## Examples

- [`../apps/cohere`](../apps/cohere) - sync and async CLI demo.
