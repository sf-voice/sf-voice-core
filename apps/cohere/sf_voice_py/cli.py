"""CLI entry point — four subcommands: ingest, search, list, demo."""

import argparse
import asyncio
import sys
import time

from sf_voice import SfVoiceMedia, AsyncSfVoiceMedia

from .config import config


def _client() -> SfVoiceMedia:
    """
    Create and return an SfVoiceMedia client configured with the application's settings.
    
    Returns:
        SfVoiceMedia: Client instance initialized with config.api_key and config.base_url.
    """
    return SfVoiceMedia(api_key=config.api_key, base_url=config.base_url)


def _print_results(results: list) -> None:
    """
    Prints a formatted list of search results to stdout.
    
    When `results` is empty or falsy, prints "  (no results)". Otherwise prints one indexed line per result containing the score (two decimal places), a start–end time range formatted as M:SS, and the result's `match_type`.
    
    Parameters:
        results (list): Iterable of result objects with attributes `start_ms` (int), `end_ms` (int), `score` (float), and `match_type` (str).
    """
    if not results:
        print("  (no results)")
        return
    for i, r in enumerate(results, 1):
        start = _ms_to_time(r.start_ms)
        end = _ms_to_time(r.end_ms)
        print(f"  {i}. score={r.score:.2f}  {start}–{end}  {r.match_type}")


def _ms_to_time(ms: int) -> str:
    """
    Format a duration given in milliseconds as an `M:SS` timestamp.
    
    Parameters:
        ms (int): Duration in milliseconds; fractional seconds are truncated.
    
    Returns:
        str: A timestamp string in `M:SS` where `M` is minutes and `SS` is two-digit seconds.
    """
    s = ms // 1000
    return f"{s // 60}:{s % 60:02d}"


# ── subcommand handlers ───────────────────────────────────────────────────────

def cmd_ingest(args: argparse.Namespace) -> None:
    """
    Submit a media URL for ingestion and wait until indexing completes.
    
    Parameters:
        args (argparse.Namespace): Parsed CLI arguments with attributes:
            url (str): URL of the media to ingest.
            title (str): Optional title to attach to the asset.
            type (str): Optional media type (e.g., "audio" or "video").
    """
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
    """
    Run a semantic search against indexed media and print formatted results.
    
    Parameters:
        args (argparse.Namespace): CLI arguments with the following fields:
            - query: search query string.
            - types: optional comma-separated string of media types to restrict the search.
            - asset_id: optional asset identifier to restrict the search to a single asset.
    """
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
    """
    List indexed assets and print each asset's status, title (or id), and duration.
    
    Parameters:
        args (argparse.Namespace): CLI arguments with `page` (int) for the page number and `limit` (int) for items per page.
    """
    client = _client()
    resp = client.list_assets(page=args.page, limit=args.limit)
    print(f"assets ({resp.page_info.total} total):")
    for asset in resp.items:
        dur = f"  {_ms_to_time(asset.duration_ms)}" if asset.duration_ms else ""
        title = (asset.metadata or {}).get("title", asset.id)
        print(f"  {asset.status:10}  {title}{dur}")


def cmd_demo(args: argparse.Namespace) -> None:
    """
    Run the demo sequence: execute the synchronous demo then the asynchronous demo using the provided URL and query.
    
    Parameters:
        args (argparse.Namespace): Parsed CLI arguments. Must provide `url` (str) and `query` (str) attributes used by the demos.
    """
    from .demo import run_sync_demo, run_async_demo

    print("=== sync demo ===")
    run_sync_demo(args.url, args.query)

    print("\n=== async demo ===")
    asyncio.run(run_async_demo(args.url, args.query))


# ── parser ────────────────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    """
    Builds and returns the command-line argument parser for the sf_demo CLI.
    
    The returned parser is configured with four required subcommands:
    - ingest: accepts a media URL and optional --title and --type (video|audio).
    - search: accepts a query and optional --types (comma-separated) and --asset-id.
    - list: accepts pagination options --page and --limit.
    - demo: accepts a URL and a query to run the full sync and async demo.
    
    Returns:
        argparse.ArgumentParser: Configured parser ready to parse CLI arguments for the sf_demo tool.
    """
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
    """
    Parse command-line arguments and invoke the selected subcommand handler.
    
    Builds the CLI parser, parses sys.argv, and dispatches execution to the matching handler for the "ingest", "search", "list", or "demo" subcommand.
    """
    parser = build_parser()
    args = parser.parse_args()

    handlers = {
        "ingest": cmd_ingest,
        "search": cmd_search,
        "list": cmd_list,
        "demo": cmd_demo,
    }
    handlers[args.command](args)
