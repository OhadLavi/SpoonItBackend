# errors.py
"""Custom exception classes for the Recipe Keeper API."""

from typing import Optional, Dict, Any


class APIError(Exception):
    """Custom API error with status code and details."""
    
    def __init__(self, message: str, status_code: int = 500, details: Optional[Dict[str, Any]] = None):
        super().__init__(message)
        self.message = message
        self.status_code = status_code
        self.details = details or {}

