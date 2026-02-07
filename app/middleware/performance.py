"""Performance monitoring middleware for tracking request metrics."""

import logging
import time
from typing import Callable

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp

logger = logging.getLogger(__name__)


class PerformanceMiddleware(BaseHTTPMiddleware):
    """Middleware for tracking and logging request performance metrics."""
    
    def __init__(
        self,
        app: ASGIApp,
        slow_request_threshold: float = 2.0,
        very_slow_request_threshold: float = 5.0
    ):
        """
        Initialize performance middleware.
        
        Args:
            app: ASGI application
            slow_request_threshold: Threshold in seconds for slow request warning
            very_slow_request_threshold: Threshold in seconds for very slow request error
        """
        super().__init__(app)
        self.slow_threshold = slow_request_threshold
        self.very_slow_threshold = very_slow_request_threshold
        
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """
        Process request and track performance metrics.
        
        Args:
            request: Incoming request
            call_next: Next middleware/handler
            
        Returns:
            Response with performance headers
        """
        # Start timing
        start_time = time.time()
        
        # Get request info
        method = request.method
        path = request.url.path
        request_id = getattr(request.state, "request_id", "unknown")
        
        # Process request
        try:
            response = await call_next(request)
        except Exception as e:
            # Log error and re-raise
            duration = time.time() - start_time
            logger.error(
                f"Request failed: {method} {path}",
                extra={
                    "request_id": request_id,
                    "method": method,
                    "path": path,
                    "duration_ms": round(duration * 1000, 2),
                    "error": str(e),
                },
                exc_info=True,
            )
            raise
        
        # Calculate duration
        duration = time.time() - start_time
        duration_ms = round(duration * 1000, 2)
        
        # Add performance header
        response.headers["X-Response-Time"] = f"{duration_ms}ms"
        
        # Log based on duration
        log_data = {
            "request_id": request_id,
            "method": method,
            "path": path,
            "status_code": response.status_code,
            "duration_ms": duration_ms,
        }
        
        if duration >= self.very_slow_threshold:
            logger.error(
                f"VERY SLOW REQUEST: {method} {path} took {duration_ms}ms",
                extra=log_data,
            )
        elif duration >= self.slow_threshold:
            logger.warning(
                f"Slow request: {method} {path} took {duration_ms}ms",
                extra=log_data,
            )
        else:
            logger.info(
                f"Request completed: {method} {path}",
                extra=log_data,
            )
        
        return response
