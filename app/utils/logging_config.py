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
    logger = logging.getLogger()
    logger.setLevel(getattr(logging, log_level.upper(), logging.INFO))

    # Remove existing handlers
    logger.handlers.clear()

    # Create console handler (stdout for Cloud Run)
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(logging.DEBUG)

    # Set JSON formatter
    formatter = CloudRunJSONFormatter()
    handler.setFormatter(formatter)

    # Add handler to logger
    logger.addHandler(handler)

    # Prevent propagation to root logger
    logger.propagate = False

