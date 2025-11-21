"""Request/response logging middleware."""

import logging
import time
from typing import Callable

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

from app.core.request_id import generate_request_id, get_request_id, set_request_id

logger = logging.getLogger(__name__)


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
        query_params = str(request.query_params) if request.query_params else ""

        # Mask API key in logs
        api_key = request.headers.get("X-API-Key") or request.headers.get("Authorization", "")
        masked_key = f"{api_key[:8]}..." if api_key else "None"

        logger.info(
            f"Request started",
            extra={
                "request_id": request_id,
                "method": method,
                "path": path,
                "query_params": query_params,
                "api_key": masked_key,
                "client_ip": request.client.host if request.client else None,
            },
        )

        # Process request
        try:
            response = await call_next(request)
            process_time = time.time() - start_time

            # Log response
            logger.info(
                f"Request completed",
                extra={
                    "request_id": request_id,
                    "method": method,
                    "path": path,
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
                f"Request failed: {str(e)}",
                extra={
                    "request_id": request_id,
                    "method": method,
                    "path": path,
                    "process_time_ms": round(process_time * 1000, 2),
                },
                exc_info=True,
            )
            raise

