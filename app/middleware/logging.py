"""Request/response logging middleware."""

import json
import logging
import time
from typing import Any, Callable, Dict, Optional, Tuple

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

from app.core.request_id import generate_request_id, get_request_id, set_request_id

logger = logging.getLogger(__name__)


async def get_request_params(request: Request) -> Dict[str, Any]:
    """
    Extract request parameters from query/path without consuming body.
    Body parameters are logged by route handlers.
    
    Args:
        request: FastAPI request object
        
    Returns:
        Dictionary with request parameters
    """
    params: Dict[str, Any] = {}
    
    # Get query parameters
    if request.query_params:
        params["query"] = dict(request.query_params)
    
    # Get path parameters
    if hasattr(request, "path_params") and request.path_params:
        params["path"] = dict(request.path_params)
    
    # Get content type for reference (but don't read body)
    content_type = request.headers.get("content-type", "").lower()
    if content_type:
        if "application/json" in content_type:
            params["content_type"] = "application/json"
            params["note"] = "Body parameters logged by route handler"
        elif "multipart/form-data" in content_type:
            params["content_type"] = "multipart/form-data"
            params["note"] = "Form data logged by route handler"
        elif "application/x-www-form-urlencoded" in content_type:
            params["content_type"] = "application/x-www-form-urlencoded"
            params["note"] = "Form data logged by route handler"
    
    return params


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """Middleware for logging requests and responses with timing."""

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """Process request and log details."""
        # Generate and set request ID
        request_id = generate_request_id()
        set_request_id(request_id)

        # Add request ID to request state
        request.state.request_id = request_id

        # Log request
        start_time = time.time()
        method = request.method
        path = request.url.path
        
        # Get route name if available
        route_name = None
        if hasattr(request, "scope") and "route" in request.scope:
            route = request.scope.get("route")
            if route:
                route_name = getattr(route, "path", None) or getattr(route, "name", None)

        # Extract request parameters (without consuming body)
        request_params = await get_request_params(request)

        # Mask sensitive data in logs
        def mask_sensitive_data(data: Any) -> Any:
            """Recursively mask sensitive fields in data."""
            if isinstance(data, dict):
                masked = {}
                for key, value in data.items():
                    key_lower = key.lower()
                    # Mask API keys, passwords, tokens, etc.
                    if any(sensitive in key_lower for sensitive in ["api_key", "password", "token", "secret", "auth"]):
                        if isinstance(value, str) and len(value) > 8:
                            masked[key] = f"{value[:8]}..."
                        else:
                            masked[key] = "***"
                    else:
                        masked[key] = mask_sensitive_data(value)
                return masked
            elif isinstance(data, list):
                return [mask_sensitive_data(item) for item in data]
            else:
                return data

        masked_params = mask_sensitive_data(request_params)

        # Get client info
        client_ip = request.client.host if request.client else None
        user_agent = request.headers.get("user-agent", "Unknown")

        log_kwargs = {
            "extra": {
                "request_id": request_id,
                "method": method,
                "path": path,
                "route": route_name,
                "params": masked_params,
                "client_ip": client_ip,
                "user_agent": user_agent,
            }
        }

        # Keep high‑volume endpoints (like image proxy) out of INFO logs
        if path == "/proxy_image":
            logger.debug(f"API Request: {method} {path}", **log_kwargs)
        else:
            logger.debug(f"API Request: {method} {path}", **log_kwargs)

        # Process request
        try:
            response = await call_next(request)
            process_time = time.time() - start_time

            # Log response at DEBUG – PerformanceMiddleware handles INFO summary
            logger.debug(
                f"API Response: {method} {path} - {response.status_code}",
                extra={
                    "request_id": request_id,
                    "method": method,
                    "path": path,
                    "route": route_name,
                    "status_code": response.status_code,
                    "process_time_ms": round(process_time * 1000, 2),
                },
            )

            # Add request ID to response header
            response.headers["X-Request-ID"] = request_id

            return response

        except Exception as e:
            process_time = time.time() - start_time
            logger.error(
                f"API Error: {method} {path} - {str(e)}",
                extra={
                    "request_id": request_id,
                    "method": method,
                    "path": path,
                    "route": route_name,
                    "params": masked_params,
                    "process_time_ms": round(process_time * 1000, 2),
                },
                exc_info=True,
            )
            raise

