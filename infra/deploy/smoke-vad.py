#!/usr/bin/env python3
"""smoke test for ellie's VAD websocket.

what we prove end-to-end:
  - TLS handshake + cloudflare → caddy → ellie path works
  - Phoenix websocket upgrade succeeds
  - bearer auth (INTERNAL_API_TOKEN) is enforced and accepts the
    configured value
  - the channel joins with the expected format-negotiation reply
    (sample_rate, samples_per_window, etc.)
  - silero actually runs — one silence window comes back with a
    numeric `prob` from the model, not from a stub

what we deliberately don't test:
  - auth rejection (covered by vad_channel_test.exs; testing it here
    means an extra connection round-trip per deploy for no new signal)
  - speech_start / speech_end transitions (would need a real audio
    fixture; out of scope for a deploy smoke)

usage:
  smoke-vad.py <ws_url> <token>
  smoke-vad.py wss://ellie-ai.sf-voice.sh/socket/vad $INTERNAL_API_TOKEN

exits:
  0 — smoke passed
  1 — anything else; stderr explains what
"""

import asyncio
import json
import struct
import sys
import time
from urllib.parse import quote

import websockets
from websockets.exceptions import WebSocketException

# silero @ 8khz: 256 samples × 4 bytes = 1024 byte windows. matches the
# default `sample_rate: 8000` we'll declare in the join payload.
WINDOW_SAMPLES = 256
WINDOW_BYTES = WINDOW_SAMPLES * 4

CONNECT_RETRIES = 5
CONNECT_BACKOFF_SECONDS = 3
RECV_TIMEOUT_SECONDS = 15


def encode_phoenix_v2_binary_push(
    join_ref: str, push_ref: str, topic: str, event: str, payload: bytes
) -> bytes:
    """phoenix v2 binary push format. matches infra/deploy/smoke-vad.py's
    rust counterpart in core/backend/api/src/vad.rs (encode_binary_push).
    keep them in sync if either side changes."""
    return (
        bytes(
            [
                0,  # kind = push from client
                len(join_ref),
                len(push_ref),
                len(topic),
                len(event),
            ]
        )
        + join_ref.encode()
        + push_ref.encode()
        + topic.encode()
        + event.encode()
        + payload
    )


async def connect_with_retry(full_url: str):
    """retry the TLS / WS handshake briefly. ellie may still be settling
    if this fires immediately after deploy."""
    last_err = None
    for attempt in range(1, CONNECT_RETRIES + 1):
        try:
            return await websockets.connect(full_url, open_timeout=10)
        except (WebSocketException, OSError) as e:
            last_err = e
            print(
                f"smoke: connect attempt {attempt}/{CONNECT_RETRIES} failed: {e}",
                file=sys.stderr,
            )
            if attempt < CONNECT_RETRIES:
                await asyncio.sleep(CONNECT_BACKOFF_SECONDS)
    raise SystemExit(f"smoke: connect gave up after {CONNECT_RETRIES} attempts: {last_err}")


async def smoke(ws_url: str, token: str) -> None:
    join_ref = "1"
    topic = f"vad:stream:smoke-{int(time.time())}"

    full_url = f"{ws_url}/websocket?vsn=2.0.0&token={quote(token, safe='')}"

    async with await connect_with_retry(full_url) as ws:
        # ── 1. join ──────────────────────────────────────────────────
        join_msg = [join_ref, join_ref, topic, "phx_join", {}]
        await ws.send(json.dumps(join_msg))

        ack = await _await_phx_reply(ws, join_ref)
        _assert_ack_shape(ack)

        # ── 2. push one silence window ──────────────────────────────
        silence_payload = struct.pack("<" + "f" * WINDOW_SAMPLES, *([0.0] * WINDOW_SAMPLES))
        assert len(silence_payload) == WINDOW_BYTES, len(silence_payload)

        push_frame = encode_phoenix_v2_binary_push(
            join_ref, "2", topic, "audio", silence_payload
        )
        await ws.send(push_frame)

        # ── 3. await a `frame` push back ────────────────────────────
        frame = await _await_event(ws, "frame")
        prob = frame.get("prob")
        if not isinstance(prob, (int, float)):
            raise SystemExit(f"smoke: frame payload missing numeric prob: {frame}")

        # silence should round-trip with a low probability; we don't
        # assert a specific upper bound because silero's output on
        # all-zero input can drift over model versions.
        print(f"smoke: ok — sample_rate={ack['sample_rate']} prob={prob}")


async def _await_phx_reply(ws, join_ref: str):
    deadline = time.monotonic() + RECV_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        raw = await asyncio.wait_for(ws.recv(), timeout=RECV_TIMEOUT_SECONDS)
        if isinstance(raw, bytes):
            continue
        msg = json.loads(raw)
        if not isinstance(msg, list) or len(msg) != 5:
            continue
        if msg[0] != join_ref or msg[3] != "phx_reply":
            continue
        if msg[4].get("status") != "ok":
            raise SystemExit(f"smoke: phx_join rejected — {msg[4]}")
        return msg[4]["response"]
    raise SystemExit(f"smoke: no phx_reply within {RECV_TIMEOUT_SECONDS}s")


async def _await_event(ws, event: str):
    deadline = time.monotonic() + RECV_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        raw = await asyncio.wait_for(ws.recv(), timeout=RECV_TIMEOUT_SECONDS)
        if isinstance(raw, bytes):
            continue
        msg = json.loads(raw)
        if isinstance(msg, list) and len(msg) == 5 and msg[3] == event:
            return msg[4]
    raise SystemExit(f"smoke: no {event!r} push within {RECV_TIMEOUT_SECONDS}s")


def _assert_ack_shape(ack: dict) -> None:
    expected = {
        "sample_rate": 8000,
        "samples_per_window": WINDOW_SAMPLES,
        "bytes_per_window": WINDOW_BYTES,
        "window_ms": 32,
        "sample_dtype": "float32_le",
    }
    for key, want in expected.items():
        got = ack.get(key)
        if got != want:
            raise SystemExit(
                f"smoke: join ack mismatch on {key!r}: want {want!r}, got {got!r} (full ack={ack})"
            )

    for key in ("speech_threshold", "silence_threshold"):
        if not isinstance(ack.get(key), (int, float)):
            raise SystemExit(f"smoke: join ack missing {key!r}: {ack}")


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)

    ws_url, token = sys.argv[1], sys.argv[2]
    if not token:
        raise SystemExit(
            "smoke: token is empty. is INTERNAL_API_TOKEN set as a GH repo secret?"
        )

    asyncio.run(smoke(ws_url, token))


if __name__ == "__main__":
    main()
