"""Request ID generation and management."""

import uuid
from contextvars import ContextVar

# Context variable to store request ID
request_id_var: ContextVar[str] = ContextVar("request_id", default="")


def generate_request_id() -> str:
    """Generate a unique request ID."""
    return str(uuid.uuid4())


def get_request_id() -> str:
    """Get current request ID from context."""
    return request_id_var.get("")


def set_request_id(request_id: str) -> None:
    """Set request ID in context."""
    request_id_var.set(request_id)

