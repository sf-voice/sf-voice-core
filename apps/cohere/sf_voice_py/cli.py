"""CLI entry point — four subcommands: ingest, search, list, demo."""

import argparse
import asyncio
import sys
import time

from sf_voice import SfVoiceMedia, AsyncSfVoiceMedia

from .config import config


def _client() -> SfVoiceMedia:
    return SfVoiceMedia(api_key=config.api_key, base_url=config.base_url)


def _print_results(results: list) -> None:
    if not results:
        print("  (no results)")
        return
    for i, r in enumerate(results, 1):
        start = _ms_to_time(r.start_ms)
        end = _ms_to_time(r.end_ms)
        print(f"  {i}. score={r.score:.2f}  {start}–{end}  {r.match_type}")


def _ms_to_time(ms: int) -> str:
    s = ms // 1000
    return f"{s // 60}:{s % 60:02d}"


# ── subcommand handlers ───────────────────────────────────────────────────────

def cmd_ingest(args: argparse.Namespace) -> None:
    """ingest a URL and poll until ready."""
    client = _client()
    print(f"ingesting {args.url} …")

    resp = client.ingest(
        source="url",
        url=args.url,
        media_type=args.type or None,
        metadata={"title": args.title} if args.title else None,
    )
    print(f"✓ submitted  asset_id={resp.asset_id}  task_id={resp.task_id}")

    print("⏳ polling", end="", flush=True)
    t0 = time.time()
    task = client.poll_task(resp.task_id, interval_s=1.5, timeout_s=300.0)
    elapsed = time.time() - t0
    print(f"\r✓ ready  asset_id={resp.asset_id}  ({elapsed:.1f}s)")

    if task.status == "failed":
        print(f"✗ indexing failed: {task.error}", file=sys.stderr)
        sys.exit(1)


def cmd_search(args: argparse.Namespace) -> None:
    """search indexed media."""
    client = _client()
    types = args.types.split(",") if args.types else None
    asset_ids = [args.asset_id] if args.asset_id else None

    resp = client.search(
        query=args.query,
        types=types,
        asset_ids=asset_ids,
    )
    print(f"🔍 results for \"{args.query}\" ({resp.page_info.total} total):")
    _print_results(resp.results)


def cmd_list(args: argparse.Namespace) -> None:
    """list all assets."""
    client = _client()
    resp = client.list_assets(page=args.page, limit=args.limit)
    print(f"assets ({resp.page_info.total} total):")
    for asset in resp.items:
        dur = f"  {_ms_to_time(asset.duration_ms)}" if asset.duration_ms else ""
        title = (asset.metadata or {}).get("title", asset.id)
        print(f"  {asset.status:10}  {title}{dur}")


def cmd_demo(args: argparse.Namespace) -> None:
    """full demo: ingest → poll → search (sync then async)."""
    from .demo import run_sync_demo, run_async_demo

    print("=== sync demo ===")
    run_sync_demo(args.url, args.query)

    print("\n=== async demo ===")
    asyncio.run(run_async_demo(args.url, args.query))


# ── parser ────────────────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="sf_demo",
        description="sf-voice media SDK demo CLI",
    )
    sub = p.add_subparsers(dest="command", required=True)

    # ingest
    ingest = sub.add_parser("ingest", help="ingest a media URL")
    ingest.add_argument("url")
    ingest.add_argument("--title", default="")
    ingest.add_argument("--type", choices=["video", "audio"], default="")

    # search
    search = sub.add_parser("search", help="semantic search")
    search.add_argument("query")
    search.add_argument("--types", help="comma-separated: visual,conversation,text_in_video")
    search.add_argument("--asset-id", dest="asset_id", default="")

    # list
    ls = sub.add_parser("list", help="list all assets")
    ls.add_argument("--page", type=int, default=1)
    ls.add_argument("--limit", type=int, default=20)

    # demo
    demo = sub.add_parser("demo", help="full ingest→poll→search demo (sync + async)")
    demo.add_argument("url")
    demo.add_argument("query")

    return p


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    handlers = {
        "ingest": cmd_ingest,
        "search": cmd_search,
        "list": cmd_list,
        "demo": cmd_demo,
    }
    handlers[args.command](args)
