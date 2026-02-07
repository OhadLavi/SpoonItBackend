""""Recipe extraction endpoints."""

import asyncio
import logging
import time
from typing import List, Optional, Tuple

from fastapi import (
    APIRouter,
    Body,
    Depends,
    File,
    Form,
    HTTPException,
    Request,
    UploadFile,
    status,
)
from pydantic import BaseModel

from app.api.dependencies import get_recipe_extractor
from app.config import settings
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


# -----------------------
# Performance / safety
# -----------------------

# Keep this LOWER than Cloud Run timeout, so *your app* returns a response (with CORS),
# instead of the gateway killing it and returning 504 without headers.
IMAGE_EXTRACT_TIMEOUT_S = 110.0
URL_EXTRACT_TIMEOUT_S = 120.0

# Resize/compress before sending to Gemini (big speed win)
VISION_MAX_DIM = 1400
JPEG_QUALITY = 78


def _maybe_resize_for_vision(image_bytes: bytes) -> bytes:
    """
    Downscale + compress images to reduce Gemini latency.

    Returns: new_bytes (JPEG)
    If Pillow isn't installed or processing fails, returns original bytes.
    """
    if not image_bytes:
        return image_bytes

    # If already small, don’t touch it
    if len(image_bytes) < 350_000:
        return image_bytes

    try:
        from PIL import Image  # type: ignore
        import io

        with Image.open(io.BytesIO(image_bytes)) as im:
            # Normalize to RGB; if alpha exists, composite onto white
            if im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info):
                bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
                im = Image.alpha_composite(bg, im.convert("RGBA")).convert("RGB")
            else:
                im = im.convert("RGB")

            w, h = im.size
            max_side = max(w, h)
            if max_side > VISION_MAX_DIM:
                scale = VISION_MAX_DIM / float(max_side)
                new_w = max(1, int(w * scale))
                new_h = max(1, int(h * scale))
                im = im.resize((new_w, new_h), Image.LANCZOS)

            out = io.BytesIO()
            im.save(out, format="JPEG", quality=JPEG_QUALITY, optimize=True)
            return out.getvalue()

    except Exception as e:
        logger.warning(f"Image resize/compress skipped (Pillow missing or failed): {e}")
        return image_bytes


class URLRequest(BaseModel):
    """Request model for URL extraction (JSON body)."""

    url: str


@router.post("/from-url", response_model=Recipe)
async def extract_from_url(
    request: Request,
    url: str = Form(None),
    url_request: URLRequest = Body(None),
    _: None = Depends(rate_limit_dependency),
    recipe_extractor: RecipeExtractor = Depends(get_recipe_extractor),
) -> Recipe:
    """
    Extract recipe from a public recipe URL.

    Accepts either:
    - Form data: `url` as form field (application/x-www-form-urlencoded or multipart/form-data)
    - JSON body: `{"url": "..."}` (application/json)
    """
    recipe_url = None
    content_type = request.headers.get("content-type", "").lower()

    if "application/json" in content_type:
        if url_request:
            recipe_url = url_request.url
        else:
            try:
                body = await request.json()
                recipe_url = body.get("url")
            except Exception:
                pass
    else:
        recipe_url = url

    if not recipe_url:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "Missing URL parameter. Provide 'url' in form data or JSON body."},
        )

    logger.info(
        "Route /recipes/from-url called",
        extra={
            "request_id": getattr(request.state, "request_id", None),
            "route": "/recipes/from-url",
            "params": {"url": recipe_url[:200]},
        },
    )

    try:
        # Run URL validation (includes DNS lookup) in executor to avoid blocking event loop
        loop = asyncio.get_running_loop()
        validated_url = await loop.run_in_executor(None, validate_url, recipe_url)
        return await asyncio.wait_for(
            recipe_extractor.extract_from_url(validated_url),
            timeout=URL_EXTRACT_TIMEOUT_S,
        )

    except asyncio.TimeoutError as e:
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail={
                "error": "Timeout",
                "detail": f"Recipe extraction took too long (> {URL_EXTRACT_TIMEOUT_S:.0f}s). "
                          f"Try again or use a different URL.",
            },
        ) from e
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
    """
    logger.info(
        "Route /recipes/from-image called",
        extra={
            "request_id": getattr(request.state, "request_id", None),
            "route": "/recipes/from-image",
            "params": {
                "filename": file.filename,
                "content_type": file.content_type,  # useful debug (but not trusted)
            },
        },
    )

    try:
        image_data = await file.read()
        if not image_data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={"error": "Invalid image", "detail": "Empty file"},
            )

        if len(image_data) > settings.max_request_size:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail={
                    "error": "File too large",
                    "detail": f"Max size is {settings.max_request_size} bytes",
                },
            )

        filename = file.filename or "image"

        # ✅ Robust validation: detect real mime from bytes (don’t trust UploadFile.content_type)
        from app.services.image_service import ImageService

        # validate_image returns (processed_bytes, mime_type) in your code usage
        validated_bytes, detected_mime = ImageService.validate_image(image_data, filename)

        logger.info(
            "Image validated",
            extra={
                "request_id": getattr(request.state, "request_id", None),
                "detected_mime": detected_mime,
                "bytes": len(validated_bytes),
            },
        )

        # ✅ Speed-up: resize/compress BEFORE Gemini
        t0 = time.perf_counter()
        # Offload CPU-bound image processing to executor to avoid blocking the event loop
        loop = asyncio.get_running_loop()
        optimized_bytes = await loop.run_in_executor(None, _maybe_resize_for_vision, validated_bytes)
        t_resize_ms = (time.perf_counter() - t0) * 1000.0

        if len(optimized_bytes) != len(validated_bytes):
            logger.info(
                "Image optimized for vision",
                extra={
                    "request_id": getattr(request.state, "request_id", None),
                    "orig_bytes": len(validated_bytes),
                    "opt_bytes": len(optimized_bytes),
                    "resize_ms": round(t_resize_ms, 2),
                },
            )

        # Since we encode as JPEG in _maybe_resize_for_vision, use jpg filename for downstream validators
        opt_filename = filename
        if optimized_bytes is not validated_bytes:
            opt_filename = "image.jpg"

        # ✅ Hard timeout to avoid Cloud Run gateway 504
        try:
            recipe = await asyncio.wait_for(
                recipe_extractor.extract_from_image(optimized_bytes, opt_filename),
                timeout=IMAGE_EXTRACT_TIMEOUT_S,
            )
            return recipe
        except asyncio.TimeoutError as e:
            raise HTTPException(
                status_code=status.HTTP_504_GATEWAY_TIMEOUT,
                detail={
                    "error": "Timeout",
                    "detail": f"Recipe extraction took too long (> {IMAGE_EXTRACT_TIMEOUT_S:.0f}s). "
                              f"Try a smaller/clearer image or retry.",
                },
            ) from e

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
    except HTTPException:
        raise
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
    """
    logger.info(
        "Route /recipes/generate called",
        extra={
            "request_id": getattr(request.state, "request_id", None),
            "route": "/recipes/generate",
            "params": {"ingredients": ingredients, "ingredients_count": len(ingredients)},
        },
    )

    try:
        validated_ingredients = validate_ingredients_list(ingredients)
        return await recipe_extractor.generate_from_ingredients(validated_ingredients)

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


@router.post("/upload-image")
async def upload_image(
    request: Request,
    file: UploadFile = File(...),
    _: None = Depends(rate_limit_dependency),
):
    """
    Upload and validate an image.
    """
    logger.info(
        "Route /recipes/upload-image called",
        extra={
            "request_id": getattr(request.state, "request_id", None),
            "route": "/recipes/upload-image",
            "params": {"filename": file.filename, "content_type": file.content_type},
        },
    )

    try:
        content = await file.read()
        if len(content) > settings.max_request_size:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail={
                    "error": "File too large",
                    "detail": f"Max size is {settings.max_request_size} bytes",
                },
            )

        from app.services.image_service import ImageService
        _, mime_type = ImageService.validate_image(content, file.filename or "image")

        return {
            "status": "valid",
            "filename": file.filename,
            "mime_type": mime_type,
            "size": len(content),
        }

    except ImageProcessingError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "Invalid image", "detail": str(e)},
        ) from e
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error in upload_image: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"error": "Internal server error", "detail": "An unexpected error occurred"},
        ) from e
