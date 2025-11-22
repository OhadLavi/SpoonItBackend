"""Rate limiting middleware using slowapi."""

from fastapi import Depends, Request
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from app.config import settings


def get_api_key_for_rate_limit(request: Request) -> str:
    """Get API key from request for rate limiting."""
    api_key = request.headers.get("X-API-Key")
    if not api_key:
        # Try Authorization header
        auth_header = request.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            api_key = auth_header[7:]
    return api_key or get_remote_address(request)


# Initialize limiter
limiter = Limiter(
    key_func=get_api_key_for_rate_limit,
    default_limits=[f"{settings.rate_limit_per_hour}/hour"],
    storage_uri="memory://",  # In-memory storage
)


def get_rate_limit_exceeded_handler():
    """Get rate limit exceeded handler."""
    return _rate_limit_exceeded_handler


def rate_limit_dependency(request: Request) -> None:
    """
    Rate limit dependency for FastAPI.
    
    Raises:
        RateLimitExceeded: If rate limit is exceeded
    """
    # Manually evaluate the limiter because we are not using the middleware hook.
    # slowapi's public API does not expose a "test" helper; instead `_check_request_limit`
    # raises `RateLimitExceeded` when the limit is hit. Passing the ASGI scope ensures the
    # path is available to the limiter (it expects a mapping with a "path" key).
    limiter._check_request_limit(request.scope, endpoint_func=None)

