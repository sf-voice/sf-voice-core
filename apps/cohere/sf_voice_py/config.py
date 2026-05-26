"""env-driven config — fails fast on missing required vars."""

import os


def _required(name: str) -> str:
    v = os.environ.get(name, "").strip()
    if not v:
        raise RuntimeError(f"required env var missing: {name}")
    return v


def _optional(name: str, fallback: str = "") -> str:
    return os.environ.get(name, fallback).strip() or fallback


class Config:
    api_key: str
    base_url: str
    sample_media_url: str

    def __init__(self) -> None:
        # load .env if present — optional, never required
        try:
            from dotenv import load_dotenv
            load_dotenv()
        except ImportError:
            pass

        self.api_key = _required("SF_VOICE_API_KEY")
        self.base_url = _optional("SF_VOICE_BASE_URL", "https://api.sf-voice.com")
        self.sample_media_url = _optional("SAMPLE_MEDIA_URL", "")


config = Config()
