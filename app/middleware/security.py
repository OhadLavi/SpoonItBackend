"""Security headers and CORS middleware."""

from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp

from app.config import settings


def setup_cors(app: ASGIApp) -> None:
    """Setup CORS middleware."""
    # Get allowed origins
    origins = settings.cors_origins_list
    
    # If wildcard is used, we can't use credentials (CORS security restriction)
    # So we'll allow all origins without credentials, or use explicit list with credentials
    if origins == ["*"]:
        # Wildcard: no credentials allowed
        app.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_credentials=False,
            allow_methods=["*"],
            allow_headers=["*"],
        )
    else:
        # Explicit origins: credentials allowed
        app.add_middleware(
            CORSMiddleware,
            allow_origins=origins,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )


def setup_compression(app: ASGIApp) -> None:
    """Setup GZip compression middleware."""
    app.add_middleware(GZipMiddleware, minimum_size=1000)


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Middleware to add security headers."""

    async def dispatch(self, request, call_next):
        """Add security headers to response."""
        response = await call_next(request)

        # Security headers
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"

        return response

