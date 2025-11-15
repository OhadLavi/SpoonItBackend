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
from services.gemini_service import get_gemini_model
from services.ocr_service import extract_text_from_image
from services.fetcher_service import fetch_html_content
from services.prompt_service import (
    create_custom_recipe_prompt,
    create_recipe_extraction_prompt,
    create_zyte_extraction_prompt,
)
from utils.json_repair import extract_and_parse_llm_json
from utils.normalization import normalize_recipe_fields

router = APIRouter()


# =============================================================================
# Zyte helpers
# =============================================================================


async def fetch_zyte_content(url: str) -> Dict[str, Any]:
    """
    Call Zyte API to fetch rich page content (including main article text and images).
    Returns a dict with at least: itemMain, images, headline/title, url.
    """
    if not ZYTE_API_KEY:
        raise APIError(
            "ZYTE_API_KEY is not configured",
            status_code=500,
            details={"code": "ZYTE_NOT_CONFIGURED"},
        )

    payload: Dict[str, Any] = {
        "url": url,
        "pageContent": True,
        "pageContentOptions": {"extractFrom": "httpResponseBody"},
        "followRedirect": True,
    }

    try:
        async with httpx.AsyncClient(
            timeout=HTTP_TIMEOUT, auth=(ZYTE_API_KEY, "")
        ) as client:
            resp = await client.post("https://api.zyte.com/v1/extract", json=payload)
            resp.raise_for_status()
            data = resp.json()
    except httpx.HTTPStatusError as exc:
        status = exc.response.status_code
        logger.error(
            "[ZYTE] HTTP error fetching %s: %s", url, status, exc_info=True
        )
        raise APIError(
            f"Zyte HTTP error {status}",
            status_code=502,
            details={
                "code": "ZYTE_HTTP_ERROR",
                "status_code": status,
                "url": url,
            },
        )
    except httpx.RequestError as exc:
        logger.error("[ZYTE] Request error for %s: %s", url, exc, exc_info=True)
        raise APIError(
            "Zyte request error",
            status_code=502,
            details={"code": "ZYTE_REQUEST_ERROR", "url": url, "error": str(exc)},
        )
    except Exception as exc:
        logger.error("[ZYTE] Unexpected error for %s: %s", url, exc, exc_info=True)
        raise APIError(
            "Unexpected Zyte error",
            status_code=500,
            details={"code": "ZYTE_UNEXPECTED", "url": url, "error": str(exc)},
        )

    if not isinstance(data, dict):
        raise APIError(
            "Zyte returned non-dict payload",
            status_code=502,
            details={"code": "ZYTE_BAD_FORMAT", "url": url},
        )

    logger.info("[ZYTE] Response keys: %s", list(data.keys()))

    # Try to get main article-like content
    item_main: str = ""
    page_content = data.get("pageContent")

    if isinstance(page_content, dict):
        # Some Zyte responses nest content under "itemMain"
        item_main = str(page_content.get("itemMain") or "")
    elif isinstance(page_content, str):
        # Sometimes pageContent itself is JSON-encoded
        try:
            pc_json = json.loads(page_content)
            if isinstance(pc_json, dict):
                item_main = str(pc_json.get("itemMain") or "")
            else:
                item_main = page_content
        except Exception:
            item_main = page_content or ""
    else:
        # Fallback to top-level itemMain
        item_main = str(data.get("itemMain") or "")

    item_main = item_main.strip()
    if len(item_main) < 50:
        logger.warning(
            "[ZYTE] itemMain too short or missing for %s (len=%d)",
            url,
            len(item_main),
        )
        raise APIError(
            "Zyte did not return enough page content",
            status_code=502,
            details={"code": "ZYTE_NO_PAGE_CONTENT", "url": url},
        )

    # Collect images from both top-level and pageContent
    images: List[str] = []

    def _collect_images(obj: Any) -> None:
        if isinstance(obj, dict):
            imgs = obj.get("images")
            if isinstance(imgs, list):
                for img in imgs:
                    if isinstance(img, dict):
                        src = img.get("src") or img.get("url")
                        if isinstance(src, str):
                            images.append(src)
        elif isinstance(obj, list):
            for item in obj:
                _collect_images(item)

    _collect_images(data)
    if isinstance(page_content, (dict, list)):
        _collect_images(page_content)

    # Remove duplicates while preserving order
    seen = set()
    unique_images: List[str] = []
    for img in images:
        if img not in seen:
            seen.add(img)
            unique_images.append(img)

    headline = data.get("headline") or data.get("title") or ""
    title = data.get("title") or headline
    canonical_url = data.get("canonicalUrl") or data.get("url") or url

    return {
        "itemMain": item_main,
        "headline": headline,
        "title": title,
        "images": unique_images,
        "url": canonical_url,
    }


async def extract_recipe_from_zyte(url: str) -> Dict[str, Any]:
    """
    Fetch page via Zyte and then let Gemini extract a structured recipe.
    """
    logger.info("[FLOW] extract_recipe ZYTE path START | url=%s", url)

    zyte_data = await fetch_zyte_content(url)
    item_main = zyte_data["itemMain"]

    model = get_gemini_model()
    prompt = create_zyte_extraction_prompt(item_main)

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
        logger.error("[ZYTE] Gemini call failed for %s: %s", url, exc, exc_info=True)
        raise APIError(
            "Error calling Gemini on Zyte content",
            status_code=500,
            details={"code": "LLM_ZYTE_ERROR", "url": url, "error": str(exc)},
        )

    response_text = (getattr(response, "text", None) or "").strip()
    if not response_text:
        raise APIError(
            "Gemini returned empty response for Zyte content",
            status_code=502,
            details={"code": "LLM_ZYTE_EMPTY", "url": url},
        )

    # Try direct JSON parse, then repair
    try:
        gemini_dict: Dict[str, Any] = json.loads(response_text)
    except Exception:
        try:
            gemini_dict = await extract_and_parse_llm_json(response_text)
        except Exception as exc:
            logger.error(
                "Failed to parse JSON response from Gemini (Zyte): %s",
                exc,
                exc_info=True,
            )
            raise APIError(
                f"Failed to parse JSON response from Gemini: {exc}",
                status_code=502,
                details={
                    "code": "LLM_JSON_PARSE",
                    "url": url,
                    "raw_head": response_text[:300],
                },
            )

    # Build unified recipe dict
    images = zyte_data.get("images") or []
    image_url = images[0] if images else ""

    recipe_dict: Dict[str, Any] = {
        "title": zyte_data.get("headline") or zyte_data.get("title") or "",
        "description": zyte_data.get("title") or "",
        "ingredients": gemini_dict.get("ingredients") or [],
        "ingredientsGroups": gemini_dict.get("ingredientsGroups") or [],
        "instructions": gemini_dict.get("instructions") or [],
        "prepTime": gemini_dict.get("prepTime") or 0,
        "cookTime": gemini_dict.get("cookTime") or 0,
        "servings": gemini_dict.get("servings") or 1,
        "tags": gemini_dict.get("tags") or [],
        "notes": gemini_dict.get("notes") or "",
        "source": zyte_data.get("url") or url,
        "imageUrl": image_url,
        "images": images,
    }

    # Clean instructions (strip numbering like "1. " / "1) ")
    cleaned_instructions: List[str] = []
    for step in recipe_dict.get("instructions", []):
        if not isinstance(step, str):
            continue
        cleaned = re.sub(r"^\s*\d+[\.\)]\s*", "", step).strip()
        cleaned_instructions.append(cleaned)

    # Build IngredientGroup objects if present
    ingredients_groups: Optional[List[IngredientGroup]] = None
    if recipe_dict.get("ingredientsGroups"):
        try:
            ingredients_groups = [
                IngredientGroup(
                    category=group.get("category", "").strip(),
                    ingredients=group.get("ingredients") or [],
                )
                for group in recipe_dict["ingredientsGroups"]
                if isinstance(group, dict)
            ]
        except Exception as exc:
            logger.warning(
                "Failed to parse ingredientsGroups from Zyte/Gemini: %s",
                exc,
                exc_info=True,
            )

    recipe_model = RecipeModel(
        title=recipe_dict.get("title") or "",
        description=recipe_dict.get("description") or "",
        ingredients=recipe_dict.get("ingredients") or [],
        ingredientsGroups=ingredients_groups,
        instructions=cleaned_instructions,
        prepTime=int(recipe_dict.get("prepTime") or 0),
        cookTime=int(recipe_dict.get("cookTime") or 0),
        servings=int(recipe_dict.get("servings") or 1),
        tags=recipe_dict.get("tags") or [],
        notes=recipe_dict.get("notes") or "",
        source=recipe_dict.get("source") or (zyte_data.get("url") or url),
        imageUrl=recipe_dict.get("imageUrl") or image_url,
        images=recipe_dict.get("images") or images,
    )

    logger.info("[FLOW] extract_recipe ZYTE path DONE | url=%s", url)
    return recipe_model.model_dump()


# =============================================================================
# HTML fetch helper (Playwright / httpx) with 403 -> Zyte signal
# =============================================================================


async def get_page_content(url: str) -> str:
    """
    Fetch page HTML using fetch_html_content().

    If the upstream fetcher raises an APIError with status_code=403, we re-raise
    a more specific APIError that the caller can use to trigger Zyte fallback.
    """
    try:
        page_content = await fetch_html_content(url)
        return page_content
    except APIError as api_err:
        if getattr(api_err, "status_code", None) == 403:
            logger.info(
                "[FLOW] 403 from fetch_html_content; signalling Zyte fallback | url=%s",
                url,
            )
            raise APIError(
                "Page is inaccessible (403), use Zyte fallback",
                status_code=403,
                details={"code": "FETCH_FORBIDDEN_ZYTE_FALLBACK", "url": url},
            )
        raise
    except Exception as exc:
        logger.error(
            "Unexpected error fetching page content from %s: %s",
            url,
            exc,
            exc_info=True,
        )
        raise APIError(
            "Unexpected error fetching page content",
            status_code=500,
            details={"code": "FETCH_UNEXPECTED", "url": url, "error": str(exc)},
        )


def create_extraction_prompt_from_content(page_content: str, url: str) -> str:
    """
    Create a prompt for extracting a recipe from raw page content (HTML + text).
    """
    preview = page_content[:10000]

    json_format_template = """{
  "title": "Recipe title in the original language",
  "description": "Short human-friendly description",
  "ingredients": ["ingredient 1", "ingredient 2"],
  "ingredientsGroups": [
    {
      "category": "Group title exactly as appears in the recipe (e.g. 'לבצק', 'למילוי')",
      "ingredients": ["ingredient 1", "ingredient 2"]
    }
  ],
  "instructions": ["Step 1", "Step 2"],
  "prepTime": 0,
  "cookTime": 0,
  "servings": 1,
  "tags": ["tag1", "tag2"],
  "notes": "Optional notes for the cook",
  "source": "%s",
  "imageUrl": ""
}""" % url

    return f"""
You are a world-class recipe extraction engine.

Your task:
1. Read the PAGE CONTENT below (HTML + visible text).
2. Find the *single main recipe* on the page (ignore comments, popups, ads, or unrelated recipes).
3. Extract a clean, structured JSON object describing ONLY that main recipe.
4. ALWAYS respond with **valid JSON**, matching EXACTLY the format shown in JSON_TEMPLATE below.
5. Do not include any extra keys beyond those defined in JSON_TEMPLATE.
6. Keep all text fields (title, description, ingredients, instructions) in the original page language.

PAGE URL: {url}

JSON_TEMPLATE:
{json_format_template}

PAGE CONTENT (first 10,000 chars):
{preview}
""".strip()


# =============================================================================
# /extract_recipe - main entrypoint for URL-based extraction
# =============================================================================


@router.post("/extract_recipe")
async def extract_recipe(request: RecipeExtractionRequest):
    """
    Extract a structured recipe from a URL.

    Flow:
    1. Fetch HTML via fetch_html_content().
    2. If that returns 403 -> fall back to Zyte.
    3. Send page content to Gemini with a strict JSON-only instruction.
    4. Parse JSON robustly (with repair) and map into RecipeModel.
    """
    url = (request.url or "").strip()
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")

    logger.info("[FLOW] extract_recipe START | url=%s", url)

    if not GEMINI_API_KEY:
        raise HTTPException(
            status_code=500,
            detail="GEMINI_API_KEY is not configured on the server",
        )

    try:
        # 1) Try to fetch page content normally
        try:
            logger.info("[FLOW] Fetching page content from URL: %s", url)
            page_content = await get_page_content(url)
        except APIError as api_err:
            # 2) If we get a signal to use Zyte, do that instead
            if (
                getattr(api_err, "status_code", None) == 403
                and isinstance(api_err.details, dict)
                and api_err.details.get("code") in (
                    "FETCH_FORBIDDEN_ZYTE_FALLBACK",
                    "FETCH_FORBIDDEN",
                )
            ):
                logger.info("[FLOW] Using Zyte fallback for url=%s", url)
                return await extract_recipe_from_zyte(url)
            raise

        if not page_content or len(page_content.strip()) < 100:
            raise APIError(
                "Fetched page is unexpectedly short or empty",
                status_code=502,
                details={"code": "FETCH_TOO_SHORT", "url": url},
            )

        logger.info(
            "[FLOW] Page content fetched successfully | url=%s | length=%d",
            url,
            len(page_content),
        )

        # 3) Build prompt for Gemini
        prompt = create_extraction_prompt_from_content(page_content, url)
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
            logger.error(
                "Gemini API call failed for url=%s: %s", url, exc, exc_info=True
            )
            raise APIError(
                "Error calling Gemini API for recipe extraction",
                status_code=500,
                details={"code": "LLM_CALL_ERROR", "url": url, "error": str(exc)},
            )

        response_text = (getattr(response, "text", None) or "").strip()
        if not response_text:
            raise APIError(
                "Gemini returned empty response",
                status_code=502,
                details={"code": "LLM_EMPTY", "url": url},
            )

        # 4) Parse JSON (try direct, then repair)
        try:
            recipe_dict: Dict[str, Any] = json.loads(response_text)
        except Exception:
            try:
                recipe_dict = await extract_and_parse_llm_json(response_text)
            except Exception as exc:
                logger.error(
                    "Failed to parse JSON response from Gemini: %s",
                    exc,
                    exc_info=True,
                )
                raise APIError(
                    f"Failed to parse JSON response from Gemini: {exc}",
                    status_code=502,
                    details={
                        "code": "LLM_JSON_PARSE",
                        "url": url,
                        "raw_head": response_text[:300],
                    },
                )

        # Ensure source is set
        recipe_dict.setdefault("source", url)

        # Clean instructions (strip leading numbering)
        cleaned_instructions: List[str] = []
        for step in recipe_dict.get("instructions") or []:
            if not isinstance(step, str):
                continue
            cleaned = re.sub(r"^\s*\d+[\.\)]\s*", "", step).strip()
            cleaned_instructions.append(cleaned)

        # Build IngredientGroup objects if present
        ingredients_groups: Optional[List[IngredientGroup]] = None
        if recipe_dict.get("ingredientsGroups"):
            try:
                ingredients_groups = [
                    IngredientGroup(
                        category=group.get("category", "").strip(),
                        ingredients=group.get("ingredients") or [],
                    )
                    for group in recipe_dict["ingredientsGroups"]
                    if isinstance(group, dict)
                ]
            except Exception as exc:
                logger.warning(
                    "Failed to parse ingredientsGroups from Gemini: %s",
                    exc,
                    exc_info=True,
                )

        recipe_model = RecipeModel(
            title=recipe_dict.get("title") or "",
            description=recipe_dict.get("description") or "",
            ingredients=recipe_dict.get("ingredients") or [],
            ingredientsGroups=ingredients_groups,
            instructions=cleaned_instructions,
            prepTime=int(recipe_dict.get("prepTime") or 0),
            cookTime=int(recipe_dict.get("cookTime") or 0),
            servings=int(recipe_dict.get("servings") or 1),
            tags=recipe_dict.get("tags") or [],
            notes=recipe_dict.get("notes") or "",
            source=recipe_dict.get("source") or url,
            imageUrl=recipe_dict.get("imageUrl") or "",
        )

        logger.info("[FLOW] extract_recipe DONE | url=%s", url)
        return recipe_model.model_dump()

    except APIError as api_err:
        # Re-raise as HTTPException to keep original status + details
        logger.error(
            "APIError in extract_recipe | url=%s | code=%s | details=%s",
            url,
            getattr(api_err, "status_code", None),
            getattr(api_err, "details", None),
            exc_info=True,
        )
        raise HTTPException(
            status_code=getattr(api_err, "status_code", 500),
            detail=getattr(api_err, "message", str(api_err)),
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.error(
            "Unexpected error in extract_recipe for url=%s: %s",
            url,
            exc,
            exc_info=True,
        )
        raise HTTPException(
            status_code=500,
            detail=f"Unexpected error extracting recipe: {exc}",
        )


# =============================================================================
# /extract_recipe_from_image - OCR + Gemini / Ollama
# =============================================================================


@router.post("/extract_recipe_from_image")
async def extract_recipe_from_image(request: ImageExtractionRequest):
    """
    Extract a recipe from a single image (base64-encoded).
    """
    if not request.image_base64:
        raise HTTPException(status_code=400, detail="image_base64 is required")

    try:
        image_bytes = base64.b64decode(request.image_base64)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid base64 image data")

    try:
        ocr_text = await extract_text_from_image(image_bytes)
    except Exception as exc:
        logger.error("OCR extraction failed: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=500, detail=f"Error extracting text from image: {exc}"
        )

    model = get_gemini_model()
    prompt = create_recipe_extraction_prompt(ocr_text)

    try:
        response = model.generate_content(
            prompt,
            generation_config={
                "temperature": 0.2,
                "max_output_tokens": 1024,
                "response_mime_type": "application/json",
            },
        )
    except Exception as exc:
        logger.error("Gemini API call failed for OCR: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Error calling Gemini API for image extraction: {exc}",
        )

    response_text = (getattr(response, "text", None) or "").strip()
    if not response_text:
        raise HTTPException(
            status_code=502, detail="Gemini returned empty response for image"
        )

    # Try JSON parse with repair
    try:
        recipe_dict: Dict[str, Any] = json.loads(response_text)
    except Exception:
        recipe_dict = await extract_and_parse_llm_json(response_text)

    recipe_dict = normalize_recipe_fields(recipe_dict)
    recipe_model = RecipeModel(**recipe_dict)

    return recipe_model.model_dump()


# =============================================================================
# /upload_recipe_image - legacy image upload endpoint using form-data
# =============================================================================


@router.post("/upload_recipe_image")
async def upload_recipe_image(file: UploadFile = File(...)):
    """
    Extract a recipe from an uploaded image file (multipart/form-data).
    """
    try:
        image_bytes = await file.read()
    except Exception as exc:
        logger.error("Failed to read uploaded image file: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=400, detail=f"Failed to read uploaded file: {exc}"
        )

    try:
        ocr_text = await extract_text_from_image(image_bytes)
    except Exception as exc:
        logger.error("OCR extraction failed (upload): %s", exc, exc_info=True)
        raise HTTPException(
            status_code=500, detail=f"Error extracting text from image: {exc}"
        )

    model = get_gemini_model()
    prompt = create_recipe_extraction_prompt(ocr_text)

    try:
        response = model.generate_content(
            prompt,
            generation_config={
                "temperature": 0.2,
                "max_output_tokens": 1024,
                "response_mime_type": "application/json",
            },
        )
    except Exception as exc:
        logger.error("Gemini API call failed for upload OCR: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Error calling Gemini API for image extraction: {exc}",
        )

    response_text = (getattr(response, "text", None) or "").strip()
    if not response_text:
        raise HTTPException(
            status_code=502, detail="Gemini returned empty response for image"
        )

    try:
        recipe_dict: Dict[str, Any] = json.loads(response_text)
    except Exception:
        recipe_dict = await extract_and_parse_llm_json(response_text)

    recipe_dict = normalize_recipe_fields(recipe_dict)
    recipe_model = RecipeModel(**recipe_dict)

    return recipe_model.model_dump()


# =============================================================================
# /test_zyte - simple Zyte debug endpoint
# =============================================================================


@router.get("/test_zyte")
async def test_zyte(url: str):
    """
    Simple endpoint to verify Zyte integration.
    """
    data = await fetch_zyte_content(url)
    return {
        "headline": data.get("headline"),
        "title": data.get("title"),
        "itemMain_preview": data.get("itemMain", "")[:500],
        "images": data.get("images", [])[:5],
        "url": data.get("url"),
    }


# =============================================================================
# /custom_recipe - generate a recipe from grocery list + description
# =============================================================================


@router.post("/custom_recipe")
async def custom_recipe(request: CustomRecipeRequest):
    """
    Generate a custom recipe from a list of groceries and a description.
    """
    if not request.groceries and not request.description:
        raise HTTPException(
            status_code=400,
            detail="At least one of 'groceries' or 'description' must be provided",
        )

    model = get_gemini_model()
    prompt = create_custom_recipe_prompt(
        groceries=request.groceries or "", description=request.description or ""
    )

    try:
        response = model.generate_content(
            prompt,
            generation_config={
                "temperature": 0.6,
                "max_output_tokens": 1536,
                "response_mime_type": "application/json",
            },
        )
    except Exception as exc:
        logger.error("Gemini API call failed for custom_recipe: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Error calling Gemini API for custom recipe: {exc}",
        )

    response_text = (getattr(response, "text", None) or "").strip()
    if not response_text:
        raise HTTPException(
            status_code=502, detail="Gemini returned empty response for custom_recipe"
        )

    try:
        recipe_dict: Dict[str, Any] = json.loads(response_text)
    except Exception:
        recipe_dict = await extract_and_parse_llm_json(response_text)

    recipe_dict = normalize_recipe_fields(recipe_dict)
    recipe_model = RecipeModel(**recipe_dict)

    return recipe_model.model_dump()
