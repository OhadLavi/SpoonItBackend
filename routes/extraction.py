# routes/extraction.py
"""Recipe extraction endpoints for URL, image, and custom recipes."""

import base64
import json
import re
from typing import Any, Dict, List, Optional

import httpx
from fastapi import APIRouter, File, HTTPException, UploadFile

from config import (
    GEMINI_API_KEY,
    HTTP_TIMEOUT,
    MODEL_NAME,
    OLLAMA_API_URL,
    ZYTE_API_KEY,
    logger,
)
from errors import APIError
from models import (
    CustomRecipeRequest,
    ImageExtractionRequest,
    IngredientGroup,
    RecipeExtractionRequest,
    RecipeModel,
)
from services.fetcher_service import fetch_html_content
from services.gemini_service import get_gemini_model
from services.ocr_service import extract_text_from_image
from services.prompt_service import (
    create_custom_recipe_prompt,
    create_recipe_extraction_prompt,
    create_zyte_extraction_prompt,
)
from utils.json_repair import extract_and_parse_llm_json
from utils.normalization import normalize_recipe_fields

router = APIRouter()


# =============================================================================
# ZYTE INTEGRATION
# =============================================================================


async def fetch_zyte_content(url: str) -> Dict[str, Any]:
    """
    Fetch page content via Zyte API.

    Returns the Zyte JSON payload. Raises APIError on 4xx/5xx or network issues.
    """
    if not ZYTE_API_KEY:
        raise APIError(
            code="ZYTE_DISABLED",
            message="Zyte API key is not configured on the server.",
            details={"url": url},
        )

    zyte_url = "https://api.zyte.com/v1/extract"
    payload = {
        "url": url,
        "browserHtml": True,
        "httpResponseBody": True,
        "screenshot": False,
    }

    logger.info("[ZYTE] Requesting Zyte extraction | url=%s", url)

    try:
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
            resp = await client.post(
                zyte_url,
                json=payload,
                auth=(ZYTE_API_KEY, ""),
            )
    except Exception as exc:
        logger.error("[ZYTE] Network error: %s", exc, exc_info=True)
        raise APIError(
            code="ZYTE_NETWORK_ERROR",
            message="Unexpected error while calling Zyte.",
            details={"url": url, "error": str(exc)},
        )

    if resp.status_code == 403:
        logger.warning("[ZYTE] 403 Forbidden from Zyte for url=%s", url)
        raise APIError(
            code="ZYTE_FORBIDDEN",
            message="Access denied by Zyte for this URL.",
            details={"url": url, "status_code": resp.status_code},
        )

    if resp.status_code >= 500:
        logger.error(
            "[ZYTE] Server error from Zyte | status=%s body=%s",
            resp.status_code,
            resp.text[:500],
        )
        raise APIError(
            code="ZYTE_SERVER_ERROR",
            message="Zyte is temporarily unavailable.",
            details={"url": url, "status_code": resp.status_code},
        )

    if resp.status_code >= 400:
        logger.error(
            "[ZYTE] Client error from Zyte | status=%s body=%s",
            resp.status_code,
            resp.text[:500],
        )
        raise APIError(
            code="ZYTE_CLIENT_ERROR",
            message="Zyte could not fetch the page.",
            details={"url": url, "status_code": resp.status_code},
        )

    try:
        data = resp.json()
    except json.JSONDecodeError as exc:
        logger.error(
            "[ZYTE] Failed to parse Zyte JSON | body_head=%r error=%s",
            resp.text[:200],
            exc,
            exc_info=True,
        )
        raise APIError(
            code="ZYTE_JSON_ERROR",
            message="Failed to parse Zyte response.",
            details={"url": url},
        )

    logger.info("[ZYTE] Success | url=%s", url)
    return data


async def extract_recipe_from_zyte(request: RecipeExtractionRequest) -> RecipeModel:
    """
    Fetch HTML via Zyte, then ask Gemini to extract a recipe JSON from it.
    """
    url = request.url
    logger.info("[FLOW] extract_recipe (ZYTE) START | url=%s", url)

    zyte_data = await fetch_zyte_content(url)

    # Prefer browserHtml, fall back to httpResponseBody if needed.
    page_html: Optional[str] = None
    if isinstance(zyte_data, dict):
        # Zyte often nests under "browserHtml" -> "html" or "httpResponseBody"
        page_html = zyte_data.get("browserHtml") or zyte_data.get("httpResponseBody")

    if not page_html:
        logger.error("[ZYTE] No HTML content in Zyte response for url=%s", url)
        raise APIError(
            code="ZYTE_NO_HTML",
            message="Zyte did not return HTML content.",
            details={"url": url},
        )

    # Build Gemini prompt specialized for Zyte HTML
    prompt = create_zyte_extraction_prompt(page_html, url)

    model = get_gemini_model()
    try:
        response = model.generate_content(
            prompt,
            generation_config={
                "temperature": 0.2,
                "max_output_tokens": 2048,
                "response_mime_type": "application/json",
            },
        )
    except Exception as exc:
        logger.error("[ZYTE] Gemini error during extraction: %s", exc, exc_info=True)
        raise APIError(
            code="LLM_ERROR",
            message="Unexpected error while extracting recipe with Gemini (Zyte).",
            details={"url": url, "error": str(exc)},
        )

    response_text = getattr(response, "text", None) or str(response)

    # ---- Robust JSON parsing (direct + repair) ----
    try:
        gemini_dict: Dict[str, Any] = json.loads(response_text)
    except Exception:
        try:
            gemini_dict = await extract_and_parse_llm_json(response_text)
        except Exception as exc:
            logger.error(
                "[ZYTE] Failed to parse JSON response from Gemini: %s | head=%r",
                exc,
                response_text[:200],
                exc_info=True,
            )
            raise APIError(
                code="LLM_JSON_PARSE",
                message="Failed to parse JSON response from Gemini (Zyte).",
                details={
                    "url": url,
                    "raw_head": response_text[:200],
                },
            )

    # Map from Gemini output to our RecipeModel fields (best-effort)
    recipe_dict: Dict[str, Any] = {
        "title": gemini_dict.get("title", ""),
        "description": gemini_dict.get("description", ""),
        "url": url,
        "servings": gemini_dict.get("servings"),
        "prepTimeMinutes": gemini_dict.get("prepTimeMinutes"),
        "cookTimeMinutes": gemini_dict.get("cookTimeMinutes"),
        "totalTimeMinutes": gemini_dict.get("totalTimeMinutes"),
        "ingredientsText": gemini_dict.get("ingredientsText") or "",
        "steps": gemini_dict.get("steps") or [],
        "cuisine": gemini_dict.get("cuisine"),
        "course": gemini_dict.get("course"),
        "diet": gemini_dict.get("diet"),
        "imageUrl": gemini_dict.get("imageUrl"),
    }

    # IngredientsGroups (optional)
    ingredients_groups: Optional[List[IngredientGroup]] = None
    if gemini_dict.get("ingredientsGroups"):
        try:
            ingredients_groups = [
                IngredientGroup(
                    category=(
                        group.get("category", "")
                        if isinstance(group, dict)
                        else ""
                    ),
                    ingredients=(
                        group.get("ingredients", [])
                        if isinstance(group, dict)
                        else []
                    ),
                )
                for group in gemini_dict["ingredientsGroups"]
            ]
        except Exception as exc:
            logger.warning(
                "[ZYTE] Failed to parse ingredientsGroups: %s", exc, exc_info=True
            )
            ingredients_groups = None

    recipe_dict["ingredientsGroups"] = ingredients_groups

    # Normalize and build RecipeModel
    recipe_dict = normalize_recipe_fields(recipe_dict)
    recipe_model = RecipeModel(**recipe_dict)

    logger.info(
        "[ZYTE] DONE | title=%r ings=%d steps=%d",
        recipe_model.title,
        len(recipe_model.ingredientsGroups or []),
        len(recipe_model.steps or []),
    )

    return recipe_model


# =============================================================================
# CORE EXTRACTION FROM URL (non-Zyte)
# =============================================================================


async def extract_recipe_from_url(request: RecipeExtractionRequest) -> RecipeModel:
    """
    Fetch HTML (Playwright / httpx) and have Gemini extract a structured recipe.
    """
    url = request.url
    logger.info("[FLOW] extract_recipe START | url=%s use_zyte=%s", url, request.use_zyte)

    # fetch_html_content returns (html, final_url)
    html_content, final_url = await fetch_html_content(url)

    prompt = create_recipe_extraction_prompt(html_content, final_url)

    model = get_gemini_model()
    try:
        response = model.generate_content(
            prompt,
            generation_config={
                "temperature": 0.2,
                "max_output_tokens": 2048,
                "response_mime_type": "application/json",
            },
        )
    except Exception as exc:
        logger.error("[FLOW] Gemini error during extraction: %s", exc, exc_info=True)
        raise APIError(
            code="LLM_ERROR",
            message="Unexpected error while extracting recipe with Gemini.",
            details={"url": final_url, "error": str(exc)},
        )

    response_text = getattr(response, "text", None) or str(response)

    # ---- Robust JSON parsing (direct + repair) ----
    try:
        recipe_dict: Dict[str, Any] = json.loads(response_text)
    except Exception:
        try:
            recipe_dict = await extract_and_parse_llm_json(response_text)
        except Exception as exc:
            logger.error(
                "[FLOW] Failed to parse JSON response from Gemini: %s | head=%r",
                exc,
                response_text[:200],
                exc_info=True,
            )
            raise APIError(
                code="LLM_JSON_PARSE",
                message="Failed to parse JSON response from Gemini.",
                details={
                    "url": final_url,
                    "raw_head": response_text[:200],
                },
            )

    # Ensure URL field is set
    recipe_dict.setdefault("url", final_url)

    # Normalize fields according to our internal model
    recipe_dict = normalize_recipe_fields(recipe_dict)
    recipe_model = RecipeModel(**recipe_dict)

    logger.info(
        "[FLOW] extract_recipe DONE | title=%r ings=%d steps=%d",
        recipe_model.title,
        len(recipe_model.ingredientsGroups or []),
        len(recipe_model.steps or []),
    )

    return recipe_model


# =============================================================================
# ROUTE: /extract_recipe
# =============================================================================


@router.post("/extract_recipe")
async def extract_recipe_endpoint(request: RecipeExtractionRequest) -> Dict[str, Any]:
    """
    Main endpoint: extract a recipe from a URL.

    If request.use_zyte is True, we go through Zyte; otherwise we fetch HTML
    directly (Playwright / httpx).
    """
    try:
        if getattr(request, "use_zyte", False):
            recipe_model = await extract_recipe_from_zyte(request)
        else:
            recipe_model = await extract_recipe_from_url(request)
    except APIError as api_err:
        # Let APIError bubble up as HTTP 500 with structured JSON
        logger.error(
            "[FLOW] APIError in /extract_recipe: %s | code=%s",
            api_err.message,
            api_err.code,
            exc_info=True,
        )
        raise HTTPException(
            status_code=500,
            detail={
                "code": api_err.code,
                "message": api_err.message,
                "details": api_err.details,
            },
        )

    return recipe_model.model_dump()


# =============================================================================
# ROUTE: /extract_recipe_from_image
# =============================================================================


@router.post("/extract_recipe_from_image")
async def extract_recipe_from_image(
    request: ImageExtractionRequest,
) -> Dict[str, Any]:
    """
    Extract a recipe from an image URL using OCR + Gemini/Ollama.
    """
    logger.info(
        "[FLOW] extract_recipe_from_image START | image_url=%s", request.image_url
    )

    # 1. Download + OCR
    try:
        ocr_text = await extract_text_from_image(request.image_url)
    except Exception as exc:
        logger.error(
            "[IMAGE] OCR extraction failed: %s | url=%s",
            exc,
            request.image_url,
            exc_info=True,
        )
        raise HTTPException(
            status_code=500,
            detail={
                "code": "OCR_ERROR",
                "message": "Failed to extract text from image.",
                "details": {"image_url": request.image_url},
            },
        )

    # 2. Prompt & LLM
    prompt = create_recipe_extraction_prompt(ocr_text, source_url=request.image_url)

    model = get_gemini_model()
    try:
        response = model.generate_content(
            prompt,
            generation_config={
                "temperature": 0.2,
                "max_output_tokens": 2048,
                "response_mime_type": "application/json",
            },
        )
    except Exception as exc:
        logger.error("[IMAGE] Gemini error during extraction: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "code": "LLM_ERROR",
                "message": "Unexpected error while extracting recipe from image.",
                "details": {"image_url": request.image_url, "error": str(exc)},
            },
        )

    llm_output = getattr(response, "text", None) or str(response)

    try:
        recipe_dict: Dict[str, Any] = json.loads(llm_output)
    except Exception:
        try:
            recipe_dict = await extract_and_parse_llm_json(llm_output)
        except Exception as exc:
            logger.error(
                "[IMAGE] Failed to parse JSON from Gemini: %s | head=%r",
                exc,
                llm_output[:200],
                exc_info=True,
            )
            raise HTTPException(
                status_code=500,
                detail={
                    "code": "LLM_JSON_PARSE",
                    "message": "Failed to parse JSON response from Gemini.",
                    "details": {
                        "image_url": request.image_url,
                        "raw_head": llm_output[:200],
                    },
                },
            )

    recipe_dict.setdefault("url", request.image_url)
    recipe_dict = normalize_recipe_fields(recipe_dict)
    recipe_model = RecipeModel(**recipe_dict)

    logger.info(
        "[FLOW] extract_recipe_from_image DONE | title=%r", recipe_model.title
    )
    return recipe_model.model_dump()


# =============================================================================
# ROUTE: /upload_recipe_image (file upload)
# =============================================================================


@router.post("/upload_recipe_image")
async def upload_recipe_image(file: UploadFile = File(...)) -> Dict[str, Any]:
    """
    Upload an image file and extract a recipe from it.
    """
    logger.info("[FLOW] upload_recipe_image START | filename=%s", file.filename)

    try:
        content = await file.read()
    except Exception as exc:
        logger.error("[UPLOAD] Failed to read uploaded file: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=400,
            detail={
                "code": "FILE_READ_ERROR",
                "message": "Failed to read uploaded file.",
                "details": {"filename": file.filename},
            },
        )

    # Convert file bytes to base64 for OCR service (if needed)
    image_b64 = base64.b64encode(content).decode("ascii")

    try:
        ocr_text = await extract_text_from_image(image_b64, is_base64=True)
    except Exception as exc:
        logger.error("[UPLOAD] OCR failed: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "code": "OCR_ERROR",
                "message": "Failed to extract text from uploaded image.",
                "details": {"filename": file.filename},
            },
        )

    prompt = create_recipe_extraction_prompt(ocr_text, source_url="uploaded-image")

    model = get_gemini_model()
    try:
        response = model.generate_content(
            prompt,
            generation_config={
                "temperature": 0.2,
                "max_output_tokens": 2048,
                "response_mime_type": "application/json",
            },
        )
    except Exception as exc:
        logger.error("[UPLOAD] Gemini error: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "code": "LLM_ERROR",
                "message": "Unexpected error while extracting recipe from uploaded image.",
                "details": {"filename": file.filename, "error": str(exc)},
            },
        )

    llm_output = getattr(response, "text", None) or str(response)

    try:
        recipe_dict: Dict[str, Any] = json.loads(llm_output)
    except Exception:
        try:
            recipe_dict = await extract_and_parse_llm_json(llm_output)
        except Exception as exc:
            logger.error(
                "[UPLOAD] Failed to parse JSON from Gemini: %s | head=%r",
                exc,
                llm_output[:200],
                exc_info=True,
            )
            raise HTTPException(
                status_code=500,
                detail={
                    "code": "LLM_JSON_PARSE",
                    "message": "Failed to parse JSON response from Gemini.",
                    "details": {"raw_head": llm_output[:200]},
                },
            )

    recipe_dict.setdefault("url", "uploaded-image")
    recipe_dict = normalize_recipe_fields(recipe_dict)
    recipe_model = RecipeModel(**recipe_dict)

    logger.info("[FLOW] upload_recipe_image DONE | title=%r", recipe_model.title)
    return recipe_model.model_dump()


# =============================================================================
# ROUTE: /custom_recipe
# =============================================================================


@router.post("/custom_recipe")
async def custom_recipe(request: CustomRecipeRequest) -> Dict[str, Any]:
    """
    Generate a custom recipe (not tied to a URL) from user instructions.
    """
    logger.info("[FLOW] custom_recipe START | title=%s", request.title)

    prompt = create_custom_recipe_prompt(request)

    model = get_gemini_model()
    try:
        response = model.generate_content(
            prompt,
            generation_config={
                "temperature": 0.6,
                "max_output_tokens": 2048,
                "response_mime_type": "application/json",
            },
        )
    except Exception as exc:
        logger.error("[CUSTOM] Gemini error: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "code": "LLM_ERROR",
                "message": "Unexpected error while generating custom recipe.",
                "details": {"error": str(exc)},
            },
        )

    llm_output = getattr(response, "text", None) or str(response)

    try:
        recipe_dict: Dict[str, Any] = json.loads(llm_output)
    except Exception:
        try:
            recipe_dict = await extract_and_parse_llm_json(llm_output)
        except Exception as exc:
            logger.error(
                "[CUSTOM] Failed to parse JSON from Gemini: %s | head=%r",
                exc,
                llm_output[:200],
                exc_info=True,
            )
            raise HTTPException(
                status_code=500,
                detail={
                    "code": "LLM_JSON_PARSE",
                    "message": "Failed to parse JSON response from Gemini.",
                    "details": {"raw_head": llm_output[:200]},
                },
            )

    recipe_dict.setdefault("url", "custom")
    recipe_dict = normalize_recipe_fields(recipe_dict)
    recipe_model = RecipeModel(**recipe_dict)

    logger.info("[FLOW] custom_recipe DONE | title=%r", recipe_model.title)
    return recipe_model.model_dump()
