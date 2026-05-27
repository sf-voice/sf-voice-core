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
    """
    Convert a duration in milliseconds to a minutes:seconds string.
    
    Parameters:
        ms (int): Duration in milliseconds.
    
    Returns:
        str: Time formatted as "M:SS" where minutes have no leading zeros and seconds are zero-padded to two digits.
    """
    s = ms // 1000
    return f"{s // 60}:{s % 60:02d}"


def run_sync_demo(url: str, query: str) -> None:
    """
    Run a synchronous end-to-end demo: ingest a media URL, wait for processing, then search the asset for a query and print results.
    
    Performs an ingest of the given media URL, polls the resulting task until it completes or fails, then executes a search for the provided query and prints scored match results to stdout.
    
    Parameters:
        url (str): Public URL of the media asset to ingest.
        query (str): Text query to search for in the processed asset.
    """
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
    """
    Run an asynchronous end-to-end demo that ingests a media URL, waits for processing to complete, and searches the resulting asset.
    
    Performs an ingest of the given URL, polls the ingestion task until it succeeds or fails, prints asset and task identifiers and progress, and then executes a search for the provided query printing scored matches with human-readable start/end timestamps. If the task fails, the function prints the error and returns early.
    
    Parameters:
        url (str): Source URL of the media to ingest.
        query (str): Search query to run against the processed asset.
    """
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

        print(f"  🔍 searching: \"{query}\"")
        results = await client.search(query=query)
        if not results.results:
            print("  (no results)")
        for i, r in enumerate(results.results, 1):
            start, end = _ms_to_time(r.start_ms), _ms_to_time(r.end_ms)
            print(f"  {i}. score={r.score:.2f}  {start}–{end}  {r.match_type}")
