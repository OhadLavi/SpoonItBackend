"""FastAPI application entry point."""

import logging

import httpx
from fastapi import Depends, FastAPI, HTTPException, Query, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
from slowapi.errors import RateLimitExceeded

from app.api.routes import chat, health, recipes
from app.config import settings
from app.core.request_id import get_request_id
from app.middleware.logging import RequestLoggingMiddleware
from app.middleware.performance import PerformanceMiddleware
from app.middleware.rate_limit import get_rate_limit_exceeded_handler, limiter, rate_limit_dependency
from app.middleware.security import SecurityHeadersMiddleware, setup_compression, setup_cors
from app.utils.exceptions import (
    AuthenticationError,
    GeminiError,
    ImageProcessingError,
    ScrapingError,
    SpoonItException,
    ValidationError,
)
from app.utils.logging_config import setup_logging
from app.utils.validators import validate_url

# Setup logging
setup_logging(settings.log_level)
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title="SpoonIt API",
    description="Recipe extraction and generation API using Gemini LLM",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# Add rate limiter to app
app.state.limiter = limiter

# Add exception handler for rate limiting
app.add_exception_handler(RateLimitExceeded, get_rate_limit_exceeded_handler())


# Add validation error handler for better error messages
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    """Handle request validation errors with detailed messages."""
    request_id = get_request_id()
    
    logger.warning(
        f"Validation error: {str(exc)}",
        extra={
            "request_id": request_id,
            "path": request.url.path,
            "method": request.method,
            "errors": exc.errors(),
        },
    )
    
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "error": "Validation error",
            "detail": exc.errors(),
            "request_id": request_id,
            "message": "Request validation failed. Check the 'detail' field for specific errors.",
        },
    )


# Global exception handler
@app.exception_handler(SpoonItException)
async def spoonit_exception_handler(request: Request, exc: SpoonItException) -> JSONResponse:
    """Handle custom SpoonIt exceptions."""
    request_id = get_request_id()

    if isinstance(exc, AuthenticationError):
        status_code = status.HTTP_401_UNAUTHORIZED
        error_message = "Authentication failed"
    elif isinstance(exc, ValidationError):
        status_code = status.HTTP_400_BAD_REQUEST
        error_message = "Validation error"
    elif isinstance(exc, ScrapingError):
        status_code = status.HTTP_502_BAD_GATEWAY
        error_message = "Scraping failed"
    elif isinstance(exc, GeminiError):
        status_code = status.HTTP_502_BAD_GATEWAY
        error_message = "Gemini API error"
    elif isinstance(exc, ImageProcessingError):
        status_code = status.HTTP_400_BAD_REQUEST
        error_message = "Image processing error"
    else:
        status_code = status.HTTP_500_INTERNAL_SERVER_ERROR
        error_message = "Internal server error"

    logger.error(
        f"Exception: {error_message}",
        extra={"request_id": request_id, "exception": str(exc)},
        exc_info=True,
    )

    return JSONResponse(
        status_code=status_code,
        content={
            "error": error_message,
            "detail": str(exc),
            "request_id": request_id,
        },
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Handle unexpected exceptions."""
    request_id = get_request_id()

    logger.error(
        f"Unexpected exception: {str(exc)}",
        extra={"request_id": request_id},
        exc_info=True,
    )

    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "error": "Internal server error",
            "detail": "An unexpected error occurred",
            "request_id": request_id,
        },
    )


# Add middleware (order matters!)
app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(PerformanceMiddleware, slow_request_threshold=2.0, very_slow_request_threshold=5.0)
app.add_middleware(RequestLoggingMiddleware)
# setup_compression(app)
setup_cors(app)

# Include routers
app.include_router(health.router)
app.include_router(recipes.router)
app.include_router(chat.router)


@app.on_event("startup")
async def startup_event():
    """Application startup event."""
    logger.info("SpoonIt API starting up...")
    logger.info(f"Log level: {settings.log_level}")
    logger.info(f"Rate limit: {settings.rate_limit_per_hour} requests/hour")


@app.on_event("shutdown")
async def shutdown_event():
    """Application shutdown event."""
    logger.info("SpoonIt API shutting down...")


@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "name": "SpoonIt API",
        "version": "1.0.0",
        "docs": "/docs",
    }


@app.get("/proxy_image")
async def proxy_image(url: str = Query(..., description="Image URL to proxy")):
    """
    Proxy image endpoint to avoid CORS issues.
    
    - **url**: Image URL to fetch and proxy
    - Returns the image with appropriate headers
    """
    import httpx
    
    try:
        # Validate URL
        validated_url = validate_url(url)
        
        # Fetch image
        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
            headers = {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            }
            response = await client.get(validated_url, headers=headers)
            response.raise_for_status()
            
            # Determine content type
            content_type = response.headers.get("content-type", "image/jpeg")
            
            # Return image with appropriate headers
            return Response(
                content=response.content,
                media_type=content_type,
                headers={
                    "Cache-Control": "public, max-age=3600",
                    "Access-Control-Allow-Origin": "*",
                },
            )
            
    except Exception as e:
        logger.error(f"Failed to proxy image from {url}: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"error": "Failed to proxy image", "detail": str(e)},
        ) from e

