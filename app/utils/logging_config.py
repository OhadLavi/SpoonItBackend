"""Structured logging configuration for Cloud Run."""

import json
import logging
import sys
from datetime import datetime
from typing import Any, Dict


class CloudRunJSONFormatter(logging.Formatter):
    """JSON formatter for Cloud Run structured logging."""

    def format(self, record: logging.LogRecord) -> str:
        """Format log record as JSON."""
        log_data: Dict[str, Any] = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "severity": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }

        # Add request ID if available
        if hasattr(record, "request_id"):
            log_data["request_id"] = record.request_id

        # Add all extra fields from the record
        # FastAPI/standard logging puts extra fields directly on the record
        for key, value in record.__dict__.items():
            if key not in [
                "name", "msg", "args", "created", "filename", "funcName",
                "levelname", "levelno", "lineno", "module", "msecs",
                "message", "pathname", "process", "processName", "relativeCreated",
                "thread", "threadName", "exc_info", "exc_text", "stack_info",
                "asctime", "taskName", "getMessage"
            ]:
                log_data[key] = value

        # Add exception info if present
        if record.exc_info:
            log_data["exception"] = self.formatException(record.exc_info)

        return json.dumps(log_data)


def setup_logging(log_level: str = "INFO") -> None:
    """
    Setup structured logging for Cloud Run.

    Args:
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
    """
    # Get root logger
    root = logging.getLogger()
    root.setLevel(getattr(logging, log_level.upper(), logging.INFO))

    # Remove existing handlers
    root.handlers.clear()

    # Create console handler (stdout for Cloud Run)
    handler = logging.StreamHandler(sys.stdout)
    # Let the root logger control effective level; keep handler permissive
    handler.setLevel(logging.NOTSET)

    # Set JSON formatter
    formatter = CloudRunJSONFormatter()
    handler.setFormatter(formatter)

    # Add handler to root logger
    root.addHandler(handler)

    # Prevent accidental double-printing from other handlers
    root.propagate = False

    # Quiet noisy third‑party libraries and server frameworks unless explicitly overridden
    noisy_loggers = [
        # HTTP clients / low-level network
        "httpx",
        "httpcore",
        "urllib3",
        # Playwright / browser automation
        "playwright",
        # Google client stack
        "google",
        "google.genai",
        "google.auth",
        # ASGI / server runtimes
        "uvicorn",
        "uvicorn.error",
        "uvicorn.access",
        "gunicorn",
        "gunicorn.error",
        "gunicorn.access",
        # AsyncIO
        "asyncio",
    ]
    for name in noisy_loggers:
        logger = logging.getLogger(name)
        logger.setLevel(logging.WARNING)
        # Also prevent propagation to avoid duplicate logs
        logger.propagate = False


