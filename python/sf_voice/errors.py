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
        """
        Initialize the SfVoiceMediaError with a human-readable message, an error code, and the HTTP status.
        
        Parameters:
            message (str): Human-readable error message; also passed to the base Exception.
            code (str): Machine-readable error code from the API (e.g., "invalid_request").
            status (int): HTTP status code associated with the error (e.g., 400).
        
        Attributes:
            message (str): Same as the provided message.
            code (str): Same as the provided code.
            status (int): Same as the provided status.
        """
        super().__init__(message)
        self.message = message
        self.code = code
        self.status = status

    @classmethod
    def from_response(cls, status: int, body: Optional[Dict[str, Any]]) -> "SfVoiceMediaError":
        """
        Create an SfVoiceMediaError from an API response body following the { "error": { "code", "message" } } envelope.
        
        If the response body contains an "error" object, its "message" and "code" fields populate the returned exception; otherwise a fallback error is returned with a status-derived message and the code "http_error".
        
        Returns:
            SfVoiceMediaError: The constructed error with `message`, `code`, and `status` set.
        """
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
        """
        Provide a detailed string representation of the error for debugging.
        
        Returns:
            A string containing the error's status, code, and message.
        """
        return f"SfVoiceMediaError(status={self.status}, code={self.code!r}, message={self.message!r})"
