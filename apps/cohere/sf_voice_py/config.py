"""env-driven config — fails fast on missing required vars."""

import os


def _required(name: str) -> str:
    """
    Retrieve the trimmed value of a required environment variable.
    
    Parameters:
        name (str): Environment variable name to read.
    
    Returns:
        The environment variable's value with leading and trailing whitespace removed.
    
    Raises:
        RuntimeError: If the environment variable is missing or empty after trimming.
    """
    v = os.environ.get(name, "").strip()
    if not v:
        raise RuntimeError(f"required env var missing: {name}")
    return v


def _optional(name: str, fallback: str = "") -> str:
    """
    Retrieve an environment variable, strip surrounding whitespace, and return a fallback when the variable is missing or empty.
    
    Parameters:
    	name (str): Name of the environment variable to read.
    	fallback (str): Value to return when the environment variable is not set or is empty after stripping.
    
    Returns:
    	str: The stripped value of the environment variable, or `fallback` if the result is an empty string.
    """
    return os.environ.get(name, fallback).strip() or fallback


class Config:
    api_key: str
    base_url: str
    sample_media_url: str

    def __init__(self) -> None:
        # load .env if present — optional, never required
        """
        Initialize the Config by optionally loading a .env file and populating attributes from environment variables.
        
        Attempts to load a `.env` file using `python-dotenv` if available (silently ignores ImportError). Sets:
        - `self.api_key` from `SF_VOICE_API_KEY` (raises RuntimeError if missing or blank).
        - `self.base_url` from `SF_VOICE_BASE_URL`, defaulting to "https://api.sf-voice.com".
        - `self.sample_media_url` from `SAMPLE_MEDIA_URL`, defaulting to an empty string.
        """
        try:
            from dotenv import load_dotenv
            load_dotenv()
        except ImportError:
            pass

        self.api_key = _required("SF_VOICE_API_KEY")
        self.base_url = _optional("SF_VOICE_BASE_URL", "https://api.sf-voice.com")
        self.sample_media_url = _optional("SAMPLE_MEDIA_URL", "")


config = Config()
