"""
error types for the sf-voice-media SDK.
all non-2xx responses raise SfVoiceMediaError with structured fields
extracted from the API's standard error envelope.
"""

from __future__ import annotations

from typing import Any, Dict, Optional


class SfVoiceMediaError(Exception):
    """raised on any non-2xx response from the API."""

    def __init__(self, message: str, code: str, status: int) -> None:
        super().__init__(message)
        self.message = message
        self.code = code
        self.status = status

    @classmethod
    def from_response(cls, status: int, body: Optional[Dict[str, Any]]) -> "SfVoiceMediaError":
        """build from the API's standard { error: { code, message } } envelope."""
        if isinstance(body, dict) and isinstance(body.get("error"), dict):
            err = body["error"]
            return cls(
                message=err.get("message", "unknown error"),
                code=err.get("code", "unknown"),
                status=status,
            )
        # fall back gracefully when the body is missing or malformed
        return cls(
            message=f"request failed with status {status}",
            code="http_error",
            status=status,
        )

    def __repr__(self) -> str:
        return f"SfVoiceMediaError(status={self.status}, code={self.code!r}, message={self.message!r})"
