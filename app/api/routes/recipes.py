"""Recipe extraction endpoints."""

import logging
from typing import List

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile, status
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from app.api.dependencies import get_recipe_extractor
from app.core.request_id import get_request_id
from app.middleware.rate_limit import rate_limit_dependency
from app.models.recipe import Recipe
from app.services.recipe_extractor import RecipeExtractor
from app.utils.exceptions import (
    GeminiError,
    ImageProcessingError,
    ScrapingError,
    ValidationError,
)
from app.utils.validators import validate_ingredients_list, validate_url

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/recipes", tags=["recipes"])


@router.post("/from-url", response_model=Recipe)
async def extract_from_url(
    request: Request,
    url: str = Form(...),
    _: None = Depends(rate_limit_dependency),
    recipe_extractor: RecipeExtractor = Depends(get_recipe_extractor),
) -> Recipe:
    """
    Extract recipe from a public recipe URL.

    - **url**: Recipe URL to extract from
    - Returns unified Recipe JSON format
    """
    # Log route-specific parameters
    logger.info(
        f"Route /recipes/from-url called",
        extra={
            "request_id": getattr(request.state, "request_id", None),
            "route": "/recipes/from-url",
            "params": {"url": url[:200]},  # Truncate long URLs
        },
    )
    
    try:
        # Validate URL
        validated_url = validate_url(url)

        # Extract recipe
        recipe = await recipe_extractor.extract_from_url(validated_url)

        return recipe

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
        logger.error(f"Unexpected error in extract_from_url: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"error": "Internal server error", "detail": "An unexpected error occurred"},
        ) from e


@router.post("/from-image", response_model=Recipe)
async def extract_from_image(
    request: Request,
    file: UploadFile = File(...),
    _: None = Depends(rate_limit_dependency),
    recipe_extractor: RecipeExtractor = Depends(get_recipe_extractor),
) -> Recipe:
    """
    Extract recipe from an uploaded image.

    - **file**: Image file (JPEG, PNG, or WebP, max 10MB)
    - Returns unified Recipe JSON format
    """
    # Log route-specific parameters
    logger.info(
        f"Route /recipes/from-image called",
        extra={
            "request_id": getattr(request.state, "request_id", None),
            "route": "/recipes/from-image",
            "params": {
                "filename": file.filename,
                "content_type": file.content_type,
                "size": getattr(file, "size", "unknown"),
            },
        },
    )
    
    try:
        # Read file content
        image_data = await file.read()
        filename = file.filename or "image"

        # Extract recipe
        recipe = await recipe_extractor.extract_from_image(image_data, filename)

        return recipe

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
        logger.error(f"Unexpected error in extract_from_image: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"error": "Internal server error", "detail": "An unexpected error occurred"},
        ) from e


@router.post("/generate", response_model=Recipe)
async def generate_recipe(
    request: Request,
    ingredients: List[str] = Form(...),
    _: None = Depends(rate_limit_dependency),
    recipe_extractor: RecipeExtractor = Depends(get_recipe_extractor),
) -> Recipe:
    """
    Generate a recipe from a list of ingredients.

    - **ingredients**: List of ingredient strings
    - Returns unified Recipe JSON format
    """
    # Log route-specific parameters
    logger.info(
        f"Route /recipes/generate called",
        extra={
            "request_id": getattr(request.state, "request_id", None),
            "route": "/recipes/generate",
            "params": {"ingredients": ingredients, "ingredients_count": len(ingredients)},
        },
    )
    
    try:
        # Validate ingredients
        validated_ingredients = validate_ingredients_list(ingredients)

        # Generate recipe
        recipe = await recipe_extractor.generate_from_ingredients(validated_ingredients)

        return recipe

    except ValidationError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "Invalid ingredients", "detail": str(e)},
        ) from e
    except GeminiError as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"error": "Failed to generate recipe", "detail": str(e)},
        ) from e
    except Exception as e:
        logger.error(f"Unexpected error in generate_recipe: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"error": "Internal server error", "detail": "An unexpected error occurred"},
        ) from e

