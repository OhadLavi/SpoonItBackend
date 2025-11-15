# routes/extraction.py
"""Recipe extraction endpoints for URL, image, and custom recipes."""

from __future__ import annotations

import base64
from typing import Any, Dict

from fastapi import APIRouter, File, HTTPException, UploadFile

from config import GEMINI_API_KEY, logger
from errors import APIError
from models import CustomRecipeRequest, ImageExtractionRequest, RecipeExtractionRequest
from services.fetcher_service import fetch_html_content, fetch_zyte_article, html_to_text
from services.gemini_service import generate_json_from_prompt
from services.ocr_service import extract_text_from_image
from services.prompt_service import (
    create_custom_recipe_prompt,
    create_recipe_extraction_prompt,
)
from utils.normalization import normalize_recipe_fields

router = APIRouter()


# ---------------------------------------------------------------------------
# Helper: merge Gemini dict with Zyte/meta and normalize to RecipeModel
# ---------------------------------------------------------------------------
def _merge_with_meta(
    recipe_dict: Dict[str, Any],
    *,
    url: str,
    title: str | None = None,
    description: str | None = None,
    main_image: str | None = None,
    images: list[str] | None = None,
):
    merged = dict(recipe_dict)

    if not merged.get("title") and title:
        merged["title"] = title
    if not merged.get("description") and description:
        merged["description"] = description
    if not merged.get("source"):
        merged["source"] = url
    if main_image and not merged.get("imageUrl"):
        merged["imageUrl"] = main_image
    if images and not merged.get("images"):
        merged["images"] = images

    return normalize_recipe_fields(merged)


# ---------------------------------------------------------------------------
# Main URL → recipe endpoint
# ---------------------------------------------------------------------------
@router.post("/extract_recipe")
async def extract_recipe(request: RecipeExtractionRequest):
    """
    Extract recipe from URL using:
    1) Our own scraping (httpx / Playwright / Jina)
    2) Zyte article fallback IF the site blocks us
    3) Gemini for structured recipe extraction (single source of truth)
    """
    url = request.url.strip()
    logger.info("[FLOW] extract_recipe START | url=%s", url)

    if not url.startswith("http"):
        raise HTTPException(status_code=400, detail="Invalid URL")

    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY not configured")

    page_text: str | None = None
    meta: Dict[str, Any] = {
        "url": url,
        "title": "",
        "description": "",
        "main_image": "",
        "images": [],
    }

    # 1) If client sends HTML, prefer that
    if request.html_content:
        logger.info("[FLOW] Using client-provided html_content (len=%d)", len(request.html_content))
        page_text = html_to_text(request.html_content)

    # 2) Otherwise scrape ourselves
    if not page_text:
        try:
            logger.info("[FLOW] Fetching page content from URL via fetch_html_content")
            page_text = await fetch_html_content(url)
        except APIError as e:
            if e.status_code == 403:
                # 3) Zyte fallback for blocked sites
                logger.info("[FLOW] fetch_html_content blocked (403) – using Zyte for %s", url)
                zyte_article = await fetch_zyte_article(url)
                page_text = zyte_article["content"]
                meta.update(zyte_article)
            else:
                raise

    # If still no meaningful content – Zyte as final attempt
    if not page_text or len(page_text.strip()) < 80:
        logger.warning("[FLOW] Fetched content too short – forcing Zyte fallback for %s", url)
        zyte_article = await fetch_zyte_article(url)
        page_text = zyte_article["content"]
        meta.update(zyte_article)

    logger.info("[FLOW] Page text ready (%d chars). Sending to Gemini.", len(page_text))

    try:
        prompt = create_recipe_extraction_prompt(page_text, url=meta.get("url", url))
        recipe_dict = await generate_json_from_prompt(
            prompt,
            max_output_tokens=8192,
            temperature=0.0,
            label="extract_recipe",
        )

        recipe_model = _merge_with_meta(
            recipe_dict,
            url=meta.get("url", url),
            title=meta.get("title") or recipe_dict.get("title"),
            description=meta.get("description") or recipe_dict.get("description"),
            main_image=meta.get("main_image"),
            images=meta.get("images"),
        )

        logger.info(
            "[FLOW] extract_recipe DONE | title=%r ings=%d steps=%d",
            recipe_model.title,
            len(recipe_model.ingredients),
            len(recipe_model.instructions),
        )
        return recipe_model.model_dump()
    except APIError:
        raise
    except Exception as e:
        logger.error("[FLOW] unexpected error in extract_recipe: %s", e, exc_info=True)
        raise APIError(
            "Error extracting recipe",
            status_code=500,
            details={"code": "UNEXPECTED", "url": url},
        )


# ---------------------------------------------------------------------------
# OCR / base64 image → recipe
# ---------------------------------------------------------------------------
@router.post("/extract_recipe_from_image")
async def extract_recipe_from_image(req: ImageExtractionRequest):
    """Extract recipe from base64 image: OCR → Gemini → RecipeModel."""
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY not configured")

    try:
        data = req.image_data
        if "," in data:
            data = data.split(",", 1)[1]
        image_bytes = base64.b64decode(data)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid base64 image data")

    text = extract_text_from_image(image_bytes)
    if not text or len(text.strip()) < 40:
        raise HTTPException(
            status_code=400, detail="Not enough text extracted from image"
        )

    logger.info("[IMG] OCR extracted %d chars", len(text))

    prompt = create_recipe_extraction_prompt(text, url=None)
    recipe_dict = await generate_json_from_prompt(
        prompt,
        max_output_tokens=4096,
        temperature=0.0,
        label="ocr_image",
    )

    recipe_model = normalize_recipe_fields(recipe_dict)
    return recipe_model.model_dump()


# ---------------------------------------------------------------------------
# Multipart image upload → recipe (same as above, different input format)
# ---------------------------------------------------------------------------
@router.post("/upload_recipe_image")
async def upload_recipe_image(file: UploadFile = File(...)):
    """Upload and extract recipe from multipart image file."""
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY not configured")

    contents = await file.read()
    if not contents:
        raise HTTPException(status_code=400, detail="Empty file")

    text = extract_text_from_image(contents)
    if not text or len(text.strip()) < 40:
        raise HTTPException(
            status_code=400, detail="Not enough text extracted from image"
        )

    logger.info("[UPLOAD_IMG] OCR extracted %d chars", len(text))

    prompt = create_recipe_extraction_prompt(text, url=None)
    recipe_dict = await generate_json_from_prompt(
        prompt,
        max_output_tokens=4096,
        temperature=0.0,
        label="upload_image",
    )

    recipe_model = normalize_recipe_fields(recipe_dict)
    return recipe_model.model_dump()


# ---------------------------------------------------------------------------
# Custom recipe from groceries
# ---------------------------------------------------------------------------
@router.post("/custom_recipe")
async def custom_recipe(req: CustomRecipeRequest):
    """Generate custom recipe from groceries and description using Gemini."""
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY not configured")

    prompt = create_custom_recipe_prompt(req.groceries, req.description)
    recipe_dict = await generate_json_from_prompt(
        prompt,
        max_output_tokens=4096,
        temperature=0.6,
        label="custom_recipe",
    )

    recipe_model = normalize_recipe_fields(recipe_dict)
    return recipe_model.model_dump()


# ---------------------------------------------------------------------------
# Debug: raw Zyte article output (optional)
# ---------------------------------------------------------------------------
@router.get("/test_zyte")
async def test_zyte(url: str):
    """Fetch raw article data from Zyte for debugging."""
    article = await fetch_zyte_article(url)
    return article
