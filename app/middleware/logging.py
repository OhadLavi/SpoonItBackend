"""Request/response logging middleware."""

import json
import logging
import time
from typing import Any, Callable, Dict, Optional, Tuple

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

from app.core.request_id import generate_request_id, get_request_id, set_request_id

logger = logging.getLogger(__name__)


async def get_request_params(request: Request) -> Tuple[Dict[str, Any], Optional[bytes]]:
    """
    Extract request parameters from body/form/query.
    Returns both params and the body bytes (to restore request).
    
    Args:
        request: FastAPI request object
        
    Returns:
        Tuple of (params dict, body bytes)
    """
    params: Dict[str, Any] = {}
    body_bytes: bytes | None = None
    
    # Get query parameters
    if request.query_params:
        params["query"] = dict(request.query_params)
    
    # Get path parameters
    if hasattr(request, "path_params") and request.path_params:
        params["path"] = dict(request.path_params)
    
    # Get body parameters based on content type
    content_type = request.headers.get("content-type", "").lower()
    
    try:
        if "application/json" in content_type:
            # JSON body - read and restore
            body_bytes = await request.body()
            if body_bytes:
                try:
                    params["body"] = json.loads(body_bytes)
                except json.JSONDecodeError:
                    params["body"] = body_bytes.decode("utf-8", errors="ignore")[:500]  # Truncate if not JSON
        elif "multipart/form-data" in content_type:
            # For multipart, we can't easily read and restore, so just log what we can
            # The route handler will handle the form parsing
            params["form"] = {"type": "multipart/form-data", "note": "Form data logged by route handler"}
        elif "application/x-www-form-urlencoded" in content_type:
            # URL-encoded form - read and restore
            body_bytes = await request.body()
            if body_bytes:
                try:
                    from urllib.parse import parse_qs
                    form_dict = {}
                    decoded = body_bytes.decode("utf-8")
                    parsed = parse_qs(decoded, keep_blank_values=True)
                    for key, values in parsed.items():
                        form_dict[key] = values[0] if len(values) == 1 else values
                    params["form"] = form_dict
                except Exception:
                    params["form"] = {"raw": body_bytes.decode("utf-8", errors="ignore")[:500]}
    except Exception as e:
        logger.warning(f"Failed to parse request body: {str(e)}")
        params["body_error"] = str(e)
    
    return params, body_bytes


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

        # Extract request parameters (and get body to restore if needed)
        request_params, body_bytes = await get_request_params(request)
        
        # Restore request body if we consumed it
        if body_bytes is not None:
            # Restore the original body for downstream handlers. After serving
            # the cached body once, delegate to the original receive callable
            # so Starlette can emit its expected `http.disconnect` event (or
            # any other follow-up messages) instead of repeatedly sending
            # `http.request`, which previously caused runtime errors during
            # response handling.
            original_receive = request._receive
            body_sent = False

            async def receive():
                nonlocal body_sent
                if not body_sent:
                    body_sent = True
                    return {"type": "http.request", "body": body_bytes, "more_body": False}

                # After the cached body has been replayed, consume messages from
                # the original receive channel. Some servers (e.g. Uvicorn with
                # h11) can emit a trailing empty `http.request` before sending
                # `http.disconnect`, which Starlette treats as a protocol error
                # during response streaming. Translate that stray message into
                # an explicit disconnect so downstream middleware receives the
                # expected signal.
                message = await original_receive()
                if message["type"] == "http.request" and not message.get("more_body"):
                    return {"type": "http.disconnect"}
                return message

            request._receive = receive

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

        logger.info(
            f"API Request: {method} {path}",
            extra={
                "request_id": request_id,
                "method": method,
                "path": path,
                "route": route_name,
                "params": masked_params,
                "client_ip": client_ip,
                "user_agent": user_agent,
            },
        )

        # Process request
        try:
            response = await call_next(request)
            process_time = time.time() - start_time

            # Log response
            logger.info(
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

