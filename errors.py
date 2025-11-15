# errors.py
"""Custom exception classes for the SpoonIt API."""

from typing import Any, Dict, Optional


class APIError(Exception):
    """Custom API error with HTTP status and optional details."""

    def __init__(
        self,
        message: str,
        status_code: int = 500,
        details: Optional[Dict[str, Any]] = None,
    ) -> None:
        super().__init__(message)
        self.message = message
        self.status_code = status_code
        self.details: Dict[str, Any] = details or {}
