"""Rate limiting middleware using slowapi."""

from fastapi import Depends, Request
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from app.config import settings


def get_api_key_for_rate_limit(request) -> str:
    """
    Get API key from request for rate limiting.
    
    Handles both Request objects and scope dicts (ASGI scope).
    """
    # Handle both Request objects and scope dicts
    if isinstance(request, dict):
        # It's a scope dict - extract headers from it
        # Headers in ASGI are a list of tuples: [(b'header-name', b'value'), ...]
        headers_list = request.get("headers", [])
        headers_dict = {}
        for key, value in headers_list:
            if isinstance(key, bytes):
                key = key.decode("latin-1").lower()
            else:
                key = str(key).lower()
            if isinstance(value, bytes):
                value = value.decode("latin-1")
            else:
                value = str(value)
            headers_dict[key] = value
        
        api_key = headers_dict.get("x-api-key")
        if not api_key:
            auth_header = headers_dict.get("authorization", "")
            if auth_header.startswith("Bearer "):
                api_key = auth_header[7:]
        
        # Get remote address from scope
        client = request.get("client")
        remote_address = client[0] if client and len(client) > 0 else "unknown"
        return api_key or remote_address
    else:
        # It's a Request object
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
    # raises `RateLimitExceeded` when the limit is hit.
    # Try passing the Request object first, fallback to scope if needed
    try:
        limiter._check_request_limit(request, endpoint_func=None)
    except (AttributeError, TypeError):
        # Fallback to scope if Request object doesn't work
        limiter._check_request_limit(request.scope, endpoint_func=None)

