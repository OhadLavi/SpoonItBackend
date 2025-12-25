"""FastAPI application entry point."""

import logging
from typing import Optional

import httpx
from fastapi import Body, Depends, FastAPI, File, HTTPException, Query, Request, status, UploadFile
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel
from slowapi.errors import RateLimitExceeded

from app.api.dependencies import get_recipe_extractor
from app.api.routes import chat, health, recipes
from app.config import settings
from app.core.request_id import get_request_id
from app.middleware.logging import RequestLoggingMiddleware
from app.middleware.performance import PerformanceMiddleware
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
    request: Request,
    req: RecipeExtractionRequest = Body(...),
    _: None = Depends(rate_limit_dependency),
    recipe_extractor: RecipeExtractor = Depends(get_recipe_extractor),
):
    """
    Legacy compatibility endpoint for /extract_recipe.
    Accepts JSON body with {"url": "..."} and returns recipe in old format.
    """
    # Log route-specific parameters
    logger.info(
        f"Route /extract_recipe called",
        extra={
            "request_id": getattr(request.state, "request_id", None),
            "route": "/extract_recipe",
            "params": {"url": req.url[:200]},  # Truncate long URLs
        },
    )
    
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
            "images": recipe.images or [],
            "ingredientGroups": [group.dict() for group in recipe.ingredientGroups] if recipe.ingredientGroups else [],
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


@app.post("/extract_recipe_from_image")
async def extract_recipe_from_image_legacy(
    request: Request,
    file: UploadFile = File(..., description="Image file to extract recipe from"),
    _: None = Depends(rate_limit_dependency),
    recipe_extractor: RecipeExtractor = Depends(get_recipe_extractor),
):
    """
    Legacy compatibility endpoint for /extract_recipe_from_image.
    Accepts multipart/form-data with an image file and returns recipe in old format.
    
    The file should be sent as multipart/form-data with field name 'file'.
    """
    # Log route-specific parameters
    logger.info(
        f"Route /extract_recipe_from_image called",
        extra={
            "request_id": getattr(request.state, "request_id", None),
            "route": "/extract_recipe_from_image",
            "params": {
                "filename": file.filename if file else None,
                "content_type": file.content_type if file else None,
            },
        },
    )
    
    try:
        # Read file content
        image_data = await file.read()
        filename = file.filename or "image"
        
        # Extract recipe using new service
        recipe = await recipe_extractor.extract_from_image(image_data, filename)
        
        # Convert new Recipe format to old format for backward compatibility
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
            "source": recipe.source or "",
            "imageUrl": str(recipe.imageUrl) if recipe.imageUrl else "",
            "images": recipe.images or [],
            "ingredientGroups": [group.dict() for group in recipe.ingredientGroups] if recipe.ingredientGroups else [],
        }
        
        return result
        
    except ImageProcessingError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "Invalid image", "detail": str(e)},
        ) from e
    except GeminiError as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"error": "Failed to extract recipe from image", "detail": str(e)},
        ) from e
    except Exception as e:
        logger.error(f"Unexpected error in extract_recipe_from_image_legacy: {str(e)}", exc_info=True)
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

