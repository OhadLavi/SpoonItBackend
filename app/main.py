"""FastAPI application entry point."""

import logging
from typing import Optional

from fastapi import Body, Depends, FastAPI, HTTPException, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from slowapi.errors import RateLimitExceeded

from app.api.dependencies import get_recipe_extractor
from app.api.routes import chat, health, recipes
from app.config import settings
from app.core.request_id import get_request_id
from app.middleware.auth import verify_api_key
from app.middleware.logging import RequestLoggingMiddleware
from app.middleware.rate_limit import get_rate_limit_exceeded_handler, limiter, rate_limit_dependency
from app.middleware.security import SecurityHeadersMiddleware, setup_compression, setup_cors
from app.services.recipe_extractor import RecipeExtractor
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
app.add_middleware(RequestLoggingMiddleware)
setup_compression(app)
setup_cors(app)

# Include routers
app.include_router(health.router)
app.include_router(recipes.router)
app.include_router(chat.router)


# =============================================================================
# Compatibility endpoints for backward compatibility with old frontend
# =============================================================================

class RecipeExtractionRequest(BaseModel):
    """Legacy request model for /extract_recipe endpoint."""
    url: str


@app.post("/extract_recipe")
async def extract_recipe_legacy(
    req: RecipeExtractionRequest = Body(...),
    api_key: str = Depends(verify_api_key),
    _: None = Depends(rate_limit_dependency),
    recipe_extractor: RecipeExtractor = Depends(get_recipe_extractor),
):
    """
    Legacy compatibility endpoint for /extract_recipe.
    Accepts JSON body with {"url": "..."} and returns recipe in old format.
    """
    try:
        # Validate URL
        validated_url = validate_url(req.url.strip())
        
        # Extract recipe using new service
        recipe = await recipe_extractor.extract_from_url(validated_url)
        
        # Convert new Recipe format to old format for backward compatibility
        # Old format: prepTime, cookTime (int), servings (int), notes (str), tags (list)
        # New format: prepTimeMinutes, cookTimeMinutes (int), servings (str), notes (list)
        result = {
            "title": recipe.title or "",
            "description": recipe.description or "",
            "ingredients": recipe.ingredients or [],
            "instructions": recipe.instructions or [],
            "prepTime": recipe.prepTimeMinutes or 0,
            "cookTime": recipe.cookTimeMinutes or 0,
            "servings": int(recipe.servings) if recipe.servings and recipe.servings.isdigit() else 1,
            "tags": [],
            "notes": " ".join(recipe.notes) if recipe.notes else "",
            "source": recipe.source or validated_url,
            "imageUrl": str(recipe.imageUrl) if recipe.imageUrl else "",
        }
        
        return result
        
    except ValidationError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "Invalid URL", "detail": str(e)},
        ) from e
    except ScrapingError as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"error": "Failed to scrape recipe URL", "detail": str(e)},
        ) from e
    except GeminiError as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"error": "Failed to extract recipe", "detail": str(e)},
        ) from e
    except Exception as e:
        logger.error(f"Unexpected error in extract_recipe_legacy: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"error": "Internal server error", "detail": "An unexpected error occurred"},
        ) from e


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

