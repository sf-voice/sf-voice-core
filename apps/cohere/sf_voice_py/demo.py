"""
full ingest → poll → search flow shown twice:
  run_sync_demo   — uses SfVoiceMedia (blocking)
  run_async_demo  — uses AsyncSfVoiceMedia (awaitable)
"""

import asyncio
import time

from sf_voice import SfVoiceMedia, AsyncSfVoiceMedia

from .config import config


def _ms_to_time(ms: int) -> str:
    s = ms // 1000
    return f"{s // 60}:{s % 60:02d}"


def run_sync_demo(url: str, query: str) -> None:
    client = SfVoiceMedia(api_key=config.api_key, base_url=config.base_url)

    print(f"  ingesting {url}")
    resp = client.ingest(source="url", url=url)
    print(f"  ✓ asset_id={resp.asset_id}  task_id={resp.task_id}")

    print("  ⏳ polling ", end="", flush=True)
    t0 = time.time()
    task = client.poll_task(resp.task_id, interval_s=1.5, timeout_s=300.0)
    elapsed = time.time() - t0

    if task.status == "failed":
        print(f"\n  ✗ failed: {task.error}")
        return

    print(f"\r  ✓ ready  ({elapsed:.1f}s)")

    print(f"  🔍 searching: \"{query}\"")
    results = client.search(query=query)
    if not results.results:
        print("  (no results)")
    for i, r in enumerate(results.results, 1):
        start, end = _ms_to_time(r.start_ms), _ms_to_time(r.end_ms)
        print(f"  {i}. score={r.score:.2f}  {start}–{end}  {r.match_type}")


async def run_async_demo(url: str, query: str) -> None:
    async with AsyncSfVoiceMedia(api_key=config.api_key, base_url=config.base_url) as client:
        print(f"  ingesting {url}")
        resp = await client.ingest(source="url", url=url)
        print(f"  ✓ asset_id={resp.asset_id}  task_id={resp.task_id}")

        print("  ⏳ polling ", end="", flush=True)
        t0 = time.time()
        task = await client.poll_task(resp.task_id, interval_s=1.5, timeout_s=300.0)
        elapsed = time.time() - t0

        if task.status == "failed":
            print(f"\n  ✗ failed: {task.error}")
            return

        print(f"\r  ✓ ready  ({elapsed:.1f}s)")

        print(f"  🔍 searching: "{query}"")
        results = await client.search(query=query)
        if not results.results:
            print("  (no results)")
        for i, r in enumerate(results.results, 1):
            start, end = _ms_to_time(r.start_ms), _ms_to_time(r.end_ms)
            print(f"  {i}. score={r.score:.2f}  {start}–{end}  {r.match_type}")
