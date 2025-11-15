"""Recipe extraction endpoints for URL, image, and custom recipes."""

import base64
import json
import re
from typing import Any, Dict, List
from urllib.parse import urljoin, urlparse

from fastapi import APIRouter, File, HTTPException, UploadFile
import httpx
from bs4 import BeautifulSoup

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
from services.prompt_service import (
    create_custom_recipe_prompt,
    create_recipe_extraction_prompt,
    create_zyte_extraction_prompt,
)
from services.fetcher_service import fetch_html_content
from utils.json_repair import extract_and_parse_llm_json
from utils.normalization import normalize_recipe_fields

router = APIRouter()


# =====================================================================
# ZYTE INTEGRATION USING ARTICLE API
# =====================================================================

async def fetch_zyte_content(url: str) -> Dict[str, Any]:
    """
    Fetch article content from Zyte API using `article` extraction.

    Expects Zyte response like:
    {
      "article": {
        "itemMain": "... main recipe text ...",
        "mainImage": { "url": "..." } OR "https://...",
        "images": [ { "url": "..." }, "https://...", ... ],
        "headline": "...",
        "title": "..."
      },
      "canonicalUrl": "...",
      "url": "..."
    }

    Returns a dict with:
    - itemMain: main article text (string)
    - mainImage: main image URL (string or "")
    - images: list[str] of all image URLs (main image first)
    - headline: article headline (string)
    - title: article/page title (string)
    - url: canonical or original URL
    """
    if not ZYTE_API_KEY:
        raise APIError(
            "ZYTE_API_KEY not configured",
            status_code=500,
            details={"code": "ZYTE_NOT_CONFIGURED"},
        )

    payload: Dict[str, Any] = {
        "url": url,
        "article": True,
        "articleOptions": {"extractFrom": "httpResponseBody"},
        "followRedirect": True,
    }

    def _normalize_image(img: Any) -> str | None:
        """Turn Zyte image object/string into a plain URL string if possible."""
        if isinstance(img, str):
            return img.strip() or None
        if isinstance(img, dict):
            # Zyte usually returns {"url": "..."}
            candidate = img.get("url") or img.get("src")
            if candidate and isinstance(candidate, str):
                return candidate.strip() or None
        return None

    try:
        async with httpx.AsyncClient(
            timeout=HTTP_TIMEOUT, auth=(ZYTE_API_KEY, "")
        ) as client:
            resp = await client.post("https://api.zyte.com/v1/extract", json=payload)
            resp.raise_for_status()
            data = resp.json()

        logger.info(
            "[ZYTE] Response keys: %s",
            list(data.keys()) if isinstance(data, dict) else "not a dict",
        )

        if not isinstance(data, dict):
            raise APIError(
                "Zyte returned unexpected response format",
                status_code=502,
                details={"code": "ZYTE_BAD_FORMAT", "url": url},
            )

        article = data.get("article") or {}
        if not isinstance(article, dict):
            article = {}

        item_main = article.get("itemMain") or article.get("body") or article.get("text") or ""
        headline = article.get("headline") or ""
        title = article.get("title") or data.get("title") or ""

        main_image_raw = article.get("mainImage")
        images_raw = article.get("images") or []

        # Normalize images
        all_images: list[str] = []
        main_image_url = _normalize_image(main_image_raw)
        if main_image_url:
            all_images.append(main_image_url)

        if isinstance(images_raw, list):
            for img in images_raw:
                url_candidate = _normalize_image(img)
                if url_candidate and url_candidate not in all_images:
                    all_images.append(url_candidate)

        if not item_main or len(str(item_main).strip()) < 100:
            logger.error(
                "[ZYTE] No usable itemMain in article for %s. article keys=%s",
                url,
                list(article.keys()),
            )
            raise APIError(
                "No article content found in Zyte response",
                status_code=502,
                details={
                    "code": "ZYTE_NO_ARTICLE_CONTENT",
                    "url": url,
                    "article_keys": list(article.keys()),
                },
            )

        canonical_url = data.get("canonicalUrl") or data.get("url") or url

        logger.info(
            "[ZYTE] Extracted article itemMain=%d chars, headline=%r, title=%r, mainImage=%r, images=%d",
            len(str(item_main)),
            (headline[:50] if headline else "none"),
            (title[:50] if title else "none"),
            main_image_url if main_image_url else "none",
            len(all_images),
        )

        return {
            "itemMain": str(item_main),
            "mainImage": main_image_url or "",
            "images": all_images,
            "headline": headline,
            "title": title,
            "url": canonical_url,
        }

    except httpx.HTTPStatusError as e:
        status_code = e.response.status_code if e.response is not None else None
        text_preview = ""
        try:
            text_preview = e.response.text[:500] if e.response is not None else ""
        except Exception:
            pass

        logger.error(
            "[ZYTE] HTTP error for %s: status=%s body=%s",
            url,
            status_code,
            text_preview or "no body",
            exc_info=True,
        )

        # Keep the special-case handling if you want (520 etc.)
        if status_code == 520:
            raise APIError(
                "Zyte API received 520 error from origin server (site may be blocking Zyte). Try again later.",
                status_code=502,
                details={
                    "code": "ZYTE_520_ERROR",
                    "url": url,
                    "message": "Origin server returned invalid response to Zyte",
                    "response_preview": text_preview,
                },
            )

        raise APIError(
            f"Zyte API request failed with status {status_code}: {str(e)}",
            status_code=502,
            details={
                "code": "ZYTE_REQUEST_FAILED",
                "url": url,
                "http_status": status_code,
                "response_preview": text_preview or None,
            },
        )

    except httpx.RequestError as e:
        logger.error("[ZYTE] Request error for %s: %s", url, e, exc_info=True)
        raise APIError(
            f"Zyte API request failed: {str(e)}",
            status_code=502,
            details={
                "code": "ZYTE_REQUEST_FAILED",
                "url": url,
                "error_type": type(e).__name__,
            },
        )

    except APIError:
        # Re-raise APIErrors as-is
        raise

    except Exception as e:
        logger.error(
            "[ZYTE] Unexpected error type=%s for %s: %r",
            type(e).__name__,
            url,
            e,
            exc_info=True,
        )
        raise APIError(
            "Unexpected error fetching from Zyte",
            status_code=500,
            details={
                "code": "ZYTE_UNEXPECTED",
                "url": url,
                "inner_type": type(e).__name__,
                "inner": str(e),
            },
        )



async def extract_recipe_from_zyte(url: str) -> Dict[str, Any]:
    """
    Extract recipe using Zyte article API and Gemini for ingredients/instructions.

    Returns a complete RecipeModel dictionary.
    """
    logger.info("[ZYTE] Fetching content from Zyte API for url=%s", url)

    zyte_data = await fetch_zyte_content(url)
    item_main = zyte_data.get("itemMain", "")

    if not item_main or len(item_main.strip()) < 100:
        raise APIError(
            "Zyte returned insufficient article content",
            status_code=502,
            details={"code": "ZYTE_INSUFFICIENT_CONTENT", "url": url},
        )

    logger.info(
        "[ZYTE] Extracting ingredients/instructions from Zyte content using Gemini"
    )
    model = get_gemini_model()
    prompt = create_zyte_extraction_prompt(item_main)

    generation_config = {
        "temperature": 0.0,
        "top_p": 0.1,
        "top_k": 1,
        "max_output_tokens": 8192,
        "response_mime_type": "application/json",
    }

    response = model.generate_content(prompt, generation_config=generation_config)
    response_text = (response.text or "").strip()

    if not response_text:
        logger.error("[ZYTE] Empty response from Gemini")
        raise APIError(
            "Model returned empty response",
            status_code=502,
            details={"code": "LLM_EMPTY", "url": url},
        )

    # Strip code fences if any
    if response_text.startswith("```"):
        lines = response_text.split("\n")
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        response_text = "\n".join(lines).strip()

    # Parse JSON with repair fallback
    try:
        recipe_from_llm = json.loads(response_text)
    except Exception:
        try:
            recipe_from_llm = await extract_and_parse_llm_json(response_text)
        except Exception as e:
            logger.error("[ZYTE] JSON parse error. Raw head: %r", response_text[:220])
            raise APIError(
                f"Failed to parse JSON response from Gemini: {str(e)}",
                status_code=500,
                details={
                    "code": "LLM_JSON_PARSE",
                    "raw_head": response_text[:500],
                    "url": url,
                },
            )

    # Images
    all_images: list[str] = zyte_data.get("images") or []
    main_image_url: str = zyte_data.get("mainImage") or (all_images[0] if all_images else "")

    # Build final recipe dict from Zyte + Gemini
    recipe_dict: Dict[str, Any] = {
        "title": zyte_data.get("headline", "") or zyte_data.get("title", "") or recipe_from_llm.get("title", ""),
        "description": zyte_data.get("title", "") or recipe_from_llm.get("description", ""),
        "ingredients": recipe_from_llm.get("ingredients", []),
        "ingredientsGroups": recipe_from_llm.get("ingredientsGroups", []),
        "instructions": recipe_from_llm.get("instructions", []),
        "prepTime": int(recipe_from_llm.get("prepTime", 0) or 0),
        "cookTime": int(recipe_from_llm.get("cookTime", 0) or 0),
        "servings": int(recipe_from_llm.get("servings", 1) or 1),
        "tags": recipe_from_llm.get("tags", []),
        "notes": recipe_from_llm.get("notes", ""),
        "source": zyte_data.get("url", url),
        "imageUrl": main_image_url,
        "images": all_images,
    }

    # Remove numbering from instructions (strip existing numbers, don't add new ones)
    instructions = recipe_dict.get("instructions", [])
    cleaned_instructions: list[str] = []
    for instruction in instructions:
        instruction_str = str(instruction).strip()
        instruction_str = re.sub(r"^\d+[\.\)]\s*", "", instruction_str)
        cleaned_instructions.append(instruction_str)
    recipe_dict["instructions"] = cleaned_instructions

    # ingredientsGroups → Pydantic objects
    ingredients_groups = None
    if recipe_dict.get("ingredientsGroups"):
        try:
            ingredients_groups = [
                IngredientGroup(
                    category=(group.get("category", "") if isinstance(group, dict) else ""),
                    ingredients=(group.get("ingredients", []) if isinstance(group, dict) else []),
                )
                for group in recipe_dict["ingredientsGroups"]
            ]
        except Exception as e:
            logger.warning("Failed to parse ingredientsGroups: %s", e)
            ingredients_groups = None

    recipe_model = RecipeModel(
        title=recipe_dict.get("title", ""),
        description=recipe_dict.get("description", ""),
        ingredients=recipe_dict.get("ingredients", []),
        ingredientsGroups=ingredients_groups,
        instructions=cleaned_instructions,
        prepTime=recipe_dict.get("prepTime", 0),
        cookTime=recipe_dict.get("cookTime", 0),
        servings=recipe_dict.get("servings", 1),
        tags=recipe_dict.get("tags", []),
        notes=recipe_dict.get("notes", ""),
        source=recipe_dict.get("source", url),
        imageUrl=recipe_dict.get("imageUrl", ""),
        images=recipe_dict.get("images", []),
    )

    logger.info(
        "[ZYTE] done | title='%s' ings=%d steps=%d prep=%d cook=%d images=%d mainImage=%r",
        recipe_model.title,
        len(recipe_model.ingredients),
        len(recipe_model.instructions),
        recipe_model.prepTime,
        recipe_model.cookTime,
        len(recipe_model.images or []),
        recipe_model.imageUrl,
    )

    return recipe_model.model_dump()


# =====================================================================
# STANDARD URL → GEMINI PATH (WITH ZYTE FALLBACK ON 403)
# =====================================================================


def extract_image_from_html(html_content: str, base_url: str) -> str:
    """
    Extract the first recipe image URL from HTML content.
    
    Returns the first valid image URL found, or empty string if none found.
    """
    try:
        soup = BeautifulSoup(html_content, 'html.parser')
        
        # Look for common recipe image selectors
        image_selectors = [
            ('img', {'class': re.compile(r'recipe|food|dish|main', re.I)}),
            ('img', {'id': re.compile(r'recipe|food|dish|main', re.I)}),
            ('img', {'data-src': True}),  # Lazy-loaded images
            ('img', {'src': True}),
        ]
        
        for tag, attrs in image_selectors:
            images = soup.find_all(tag, attrs)
            for img in images:
                # Try data-src first (lazy loading), then src
                img_url = img.get('data-src') or img.get('src') or img.get('data-lazy-src')
                if not img_url:
                    continue
                
                # Skip small images (likely icons) and data URIs
                if img_url.startswith('data:'):
                    continue
                
                # Skip common non-recipe images
                skip_patterns = ['logo', 'icon', 'avatar', 'button', 'badge', 'spinner']
                if any(pattern in img_url.lower() for pattern in skip_patterns):
                    continue
                
                # Make absolute URL if relative
                if not img_url.startswith('http'):
                    img_url = urljoin(base_url, img_url)
                
                # Validate it's a proper URL
                parsed = urlparse(img_url)
                if parsed.scheme in ('http', 'https') and parsed.netloc:
                    logger.info("[FLOW] Extracted image from HTML: %s", img_url)
                    return img_url
        
        logger.info("[FLOW] No recipe image found in HTML")
        return ""
    except Exception as e:
        logger.warning("[FLOW] Error extracting image from HTML: %s", e)
        return ""


async def get_page_content(url: str) -> str:
    """
    Fetches the page content using httpx/Playwright via fetch_html_content.
    If 403 error occurs, we signal the caller to use Zyte fallback.
    """
    try:
        text = await fetch_html_content(url)
        return text
    except APIError as api_err:
        if api_err.status_code == 403:
            logger.info(
                "[FLOW] 403 error detected in fetch_html_content, signalling Zyte fallback | url=%s",
                url,
            )
            raise APIError(
                "Page is inaccessible (403), using Zyte fallback",
                status_code=403,
                details={"code": "FETCH_FORBIDDEN_ZYTE_FALLBACK", "url": url},
            )
        raise
    except Exception as e:
        logger.error(
            "Unexpected error fetching page content from %s: %s", url, e, exc_info=True
        )
        raise APIError(
            "Unexpected error fetching page content.",
            status_code=500,
            details={"code": "FETCH_UNEXPECTED", "url": url, "error": str(e)},
        )


def create_extraction_prompt_from_content(page_content: str, url: str) -> str:
    """Create a prompt for extracting recipe from page content."""
    content_preview = page_content[:10000]

    json_format_template = """{
  "title": "Recipe Title",
  "description": "Recipe description or summary",
  "ingredients": ["ingredient 1", "ingredient 2", ...],
  "ingredientsGroups": [
    {
      "category": "Category name as written on page",
      "ingredients": ["ingredient 1", "ingredient 2"]
    }
  ],
  "instructions": ["step 1", "step 2", ...],
  "prepTime": 0,
  "cookTime": 0,
  "servings": 1,
  "tags": ["tag1", "tag2", ...],
  "notes": "Any additional notes",
  "source": "%s",
  "imageUrl": "URL of recipe image if available"
}""" % url

    return f"""🚨 CRITICAL SYSTEM INSTRUCTION 🚨
YOU ARE A DATA EXTRACTION ROBOT. YOUR ONLY JOB IS TO COPY TEXT EXACTLY AS WRITTEN.
DO NOT PARAPHRASE. DO NOT TRANSLATE. DO NOT CHANGE ANYTHING.
IF YOU CHANGE EVEN ONE WORD OR NUMBER, THE EXTRACTION HAS FAILED.

Given the following webpage text, extract the recipe information into the specified JSON format.

JSON FORMAT TO USE:
{json_format_template}

WEBPAGE TEXT:
{content_preview}

⚠️ CRITICAL - YOUR TASK IS TO COPY, NOT TO CREATE OR MODIFY ⚠️

YOU ARE A COPY MACHINE, NOT A WRITER. DO NOT CHANGE ANYTHING.

═══════════════════════════════════════════════════════════════
STEP 1: EXTRACT ALL INGREDIENTS (MANDATORY - DO NOT MISS ANY)
═══════════════════════════════════════════════════════════════

🔍 MANDATORY: SEARCH FOR INGREDIENT SECTIONS (Hebrew & English):

Hebrew patterns (MOST COMMON):
- "מצרכים למתכון:" or "מצרכים:" or "חומרים:" → Main ingredients
- "למילוי:" → Filling ingredients
- "לציפוי:" → Topping/coating ingredients  
- "לבצק:" → Dough ingredients
- "לרוטב:" → Sauce ingredients

English patterns:
- "Ingredients:", "For the filling:", "For the dough:", "For topping:"

🚨 EXTRACTION RULES (MANDATORY - NO EXCEPTIONS):

1. EXTRACT EVERY LINE UNDER INGREDIENT SECTIONS:
   - See "מצרכים למתכון:" → Extract ALL lines until next section (למילוי/לציפוי/אופן ההכנה)
   - See "למילוי:" → Extract ALL those lines too
   - See "לציפוי:" → Extract ALL those lines too
   - Keep extracting until you reach instructions section ("אופן ההכנה:" or "הוראות הכנה:")

2. USE "ingredientsGroups" STRUCTURE:
   {{
     "ingredientsGroups": [
       {{"category": "מצרכים למתכון:", "ingredients": ["ingredient 1", "ingredient 2", ...]}},
       {{"category": "למילוי:", "ingredients": ["ingredient 3", "ingredient 4", ...]}},
       {{"category": "לציפוי:", "ingredients": ["ingredient 5", "ingredient 6"]}}
     ],
     "ingredients": []
   }}

3. COPY EXACTLY - ZERO TOLERANCE FOR CHANGES:
   - "1 קילו קמח לחם/חלה/פיצה או קמח לבן רגיל" → EXACT COPY
   - "750 גר׳ בשר טחון" → EXACT COPY (NOT "750 גרם", NOT "0.75 קילו")
   - "בצל גדול חתוך לקוביות קטנות" → EXACT COPY (NOT "1 בצל", NOT "בצל")
   - "2 כפות שמרים יבשים" → EXACT COPY (NOT "2 כפות שמרים")

4. IF NO INGREDIENTS EXTRACTED = COMPLETE FAILURE:
   - Recipes ALWAYS have ingredients
   - Empty "ingredientsGroups" and "ingredients" = YOU FAILED

❌ THESE ARE COMPLETE FAILURES:
- {{"ingredientsGroups": [], "ingredients": []}} when recipe has clear ingredients
- Only extracting "מצרכים למתכון:" and skipping "למילוי:", "לציפוי:"
- Changing ANY word, number, or unit in ingredients
- Missing ingredients from sub-sections

═══════════════════════════════════════════════════════════════
STEP 2: EXTRACT TIME AND SERVINGS (MANDATORY - BE ACCURATE)
═══════════════════════════════════════════════════════════════

🔍 SEARCH FOR TIME INFORMATION:
Look for these patterns (in Hebrew and English):
- Prep time: "זמן הכנה:", "זמן הכנה", "Prep time:", "Preparation:", "Prep:", "הכנה:", etc.
- Cook time: "זמן בישול:", "זמן בישול", "Cook time:", "Cooking time:", "בישול:", etc.
- Total time: "זמן כולל:", "Total time:", "סה\"כ:", etc.
- Look for numbers followed by: "דקות", "דק'", "minutes", "min", "שעות", "hours", "hrs", etc.

🔍 SEARCH FOR SERVINGS INFORMATION:
Look for these patterns:
- "מנות:", "מנות", "Servings:", "Serves:", "מס' מנות:", "מספר מנות:", etc.
- Look for numbers like: "4 מנות", "4 servings", "לכ-4", "לכ- 4", etc.

✅ EXTRACTION RULES:
- prepTime: Extract ONLY preparation time (chopping, mixing, etc.) in MINUTES as integer
  - If you see "15 דקות" or "15 minutes" → prepTime: 15
  - If you see "30 דקות הכנה" → prepTime: 30
  - If you see "1 שעה" or "1 hour" → prepTime: 60
  - If no prep time is mentioned → prepTime: 0
  - DO NOT confuse prep time with cook time or total time

- cookTime: Extract ONLY cooking/baking time in MINUTES as integer
  - If you see "45 דקות" or "45 minutes" → cookTime: 45
  - If you see "1.5 שעות" or "1.5 hours" → cookTime: 90
  - If you see "בישול: 30 דקות" → cookTime: 30
  - If no cook time is mentioned → cookTime: 0
  - DO NOT confuse cook time with prep time or total time

- servings: Extract the number of servings as integer
  - If you see "4 מנות" or "4 servings" → servings: 4
  - If you see "לכ-6" → servings: 6
  - If you see "מס' מנות: 8" → servings: 8
  - If no servings mentioned → servings: 1 (default)
  - Extract the ACTUAL number, not a range (if you see "4-6", use 4 or the first number)

❌ COMMON MISTAKES TO AVOID:
- Setting prepTime = total time (should be separate)
- Setting cookTime = total time (should be separate)
- Confusing hours with minutes (1 hour = 60 minutes)
- Using ranges for servings (use the first number or most common)
- Setting times to 0 when they are clearly mentioned on the page
- Mixing up prep time and cook time

═══════════════════════════════════════════════════════════════
STEP 3: COPY INSTRUCTIONS EXACTLY AS WRITTEN (ZERO TOLERANCE)
═══════════════════════════════════════════════════════════════

🚨 MANDATORY RULES:
- Find the instructions section: "אופן ההכנה:" or "הוראות הכנה:" or "Instructions:"
- COPY each instruction sentence EXACTLY AS WRITTEN - word for word
- Do NOT paraphrase, summarize, rewrite, or simplify
- Do NOT change ANY words, numbers, or descriptions
- Do NOT correct spelling or grammar
- Only add step numbers (1., 2., 3., ...) at the start if not already present
- Extract ALL steps - do not skip any
- If recipe says "מחממים תנור ל 180 מעלות" → Write: "1. מחממים תנור ל 180 מעלות" (NOT "1. Preheat oven to 180 degrees")

❌ INSTRUCTION FAILURES:
- Changing "מכניסים לגומה כף גדושה מאוד של בשר" to "מכניסים כף בשר" (WRONG - removed words)
- Changing "אופים כ 20-25 דקות" to "אופים 25 דקות" (WRONG - changed range)
- Translating Hebrew to English or vice versa (WRONG - keep original language)
- Combining multiple steps into one (WRONG - keep separate)

⚠️ FINAL CHECKLIST BEFORE RESPONDING:
1. ✅ Did I extract ALL ingredients from ALL sections? (Check the entire content)
2. ✅ Did I extract prepTime correctly? (Only preparation, in minutes)
3. ✅ Did I extract cookTime correctly? (Only cooking/baking, in minutes)
4. ✅ Did I extract servings correctly? (Actual number, not range)
5. ✅ Are all ingredients copied EXACTLY as written?
6. ✅ Are all instructions copied EXACTLY as written?

IF YOU MISS ANY INGREDIENTS OR EXTRACT TIMES/SERVINGS INCORRECTLY, YOU HAVE FAILED.
YOUR JOB IS TO COPY ACCURATELY, NOT TO GUESS OR SKIP INFORMATION.
"""


@router.post("/extract_recipe")
async def extract_recipe(request: RecipeExtractionRequest):
    """
    Extract recipe from URL using Gemini API, with Zyte fallback on 403.

    This is the main endpoint used by the app.
    """
    url = request.url.strip()
    logger.info("[FLOW] extract_recipe START | url=%s", url)

    if not url.startswith("http"):
        raise HTTPException(status_code=400, detail="Invalid URL")

    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY not configured")

    try:
        logger.info("[FLOW] Fetching page content from URL: %s", url)
        try:
            page_content = await get_page_content(url)
        except APIError as api_err:
            # If fetch_html_content indicated 403 → use Zyte fallback
            error_code = api_err.details.get("code") if hasattr(api_err, "details") else None
            if api_err.status_code == 403 and error_code in (
                "FETCH_FORBIDDEN_ZYTE_FALLBACK",
                "FETCH_FORBIDDEN",
            ):
                logger.info("[FLOW] Using Zyte API fallback for url=%s", url)
                return await extract_recipe_from_zyte(url)
            raise

        if not page_content or len(page_content.strip()) < 100:
            logger.error(
                "[FLOW] Failed to fetch meaningful content from url=%s", url
            )
            raise APIError(
                "Could not fetch or parse page content",
                status_code=502,
                details={"code": "FETCH_FAILED", "url": url},
            )

        logger.info(
            "[FLOW] Page content fetched (%d chars), sending to Gemini",
            len(page_content),
        )
        
        # Extract image URL from HTML before sending to Gemini
        # This ensures we get the image even if Gemini doesn't extract it
        extracted_image_url = ""
        try:
            # Get raw HTML for image extraction (separate fetch for raw HTML)
            async with httpx.AsyncClient(timeout=HTTP_TIMEOUT, follow_redirects=True) as client:
                response = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
                response.raise_for_status()
                raw_html = response.text
                if raw_html:
                    extracted_image_url = extract_image_from_html(raw_html, url)
                    if extracted_image_url:
                        logger.info("[FLOW] Extracted image URL from HTML: %s", extracted_image_url)
        except Exception as e:
            logger.warning("[FLOW] Failed to extract image from HTML: %s", e)
        
        model = get_gemini_model()
        prompt = create_extraction_prompt_from_content(page_content, url)

        generation_config = {
            "temperature": 0.0,
            "top_p": 0.1,
            "top_k": 1,
            "max_output_tokens": 8192,
            "response_mime_type": "application/json",
        }

        response = model.generate_content(prompt, generation_config=generation_config)
        response_text = (getattr(response, "text", None) or "").strip()

        if not response_text:
            logger.error("[LLM] empty response from Gemini for url=%s", url)
            raise APIError(
                "Model returned empty response",
                status_code=502,
                details={"code": "LLM_EMPTY", "url": url},
            )

        # Parse JSON via robust repair helper
        try:
            recipe_dict: Dict[str, Any] = await extract_and_parse_llm_json(
                response_text
            )
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

        if not recipe_dict.get("source"):
            recipe_dict["source"] = url

        # Use extracted image URL if Gemini didn't provide one or if extracted one is better
        gemini_image_url = recipe_dict.get("imageUrl", "").strip()
        if not gemini_image_url and extracted_image_url:
            recipe_dict["imageUrl"] = extracted_image_url
            logger.info("[FLOW] Using HTML-extracted image URL: %s", extracted_image_url)
        elif extracted_image_url and gemini_image_url != extracted_image_url:
            # Prefer HTML-extracted URL if it's different (usually more reliable)
            recipe_dict["imageUrl"] = extracted_image_url
            logger.info("[FLOW] Overriding Gemini image URL with HTML-extracted: %s", extracted_image_url)

        # Remove numbering from instructions (strip existing numbers, don't add new ones)
        instructions = recipe_dict.get("instructions", [])
        cleaned_instructions: List[str] = []
        for instruction in instructions:
            instruction_str = str(instruction).strip()
            instruction_str = re.sub(r"^\d+[\.\)]\s*", "", instruction_str)
            cleaned_instructions.append(instruction_str)
        recipe_dict["instructions"] = cleaned_instructions

        # ingredientsGroups → Pydantic objects
        ingredients_groups = None
        if recipe_dict.get("ingredientsGroups"):
            try:
                ingredients_groups = [
                    IngredientGroup(
                        category=(
                            group.get("category", "") if isinstance(group, dict) else ""
                        ),
                        ingredients=(
                            group.get("ingredients", [])
                            if isinstance(group, dict)
                            else []
                        ),
                    )
                    for group in recipe_dict["ingredientsGroups"]
                ]
            except Exception as e:
                logger.warning("Failed to parse ingredientsGroups: %s", e)
                ingredients_groups = None

        recipe_model = RecipeModel(
            title=recipe_dict.get("title", ""),
            description=recipe_dict.get("description", ""),
            ingredients=recipe_dict.get("ingredients", []),
            ingredientsGroups=ingredients_groups,
            instructions=cleaned_instructions,
            prepTime=int(recipe_dict.get("prepTime", 0) or 0),
            cookTime=int(recipe_dict.get("cookTime", 0) or 0),
            servings=int(recipe_dict.get("servings", 1) or 1),
            tags=recipe_dict.get("tags", []),
            notes=recipe_dict.get("notes", ""),
            source=recipe_dict.get("source", url),
            imageUrl=recipe_dict.get("imageUrl", ""),
        )

        logger.info(
            "[FLOW] done via Gemini | title='%s' ings=%d steps=%d prep=%d cook=%d",
            recipe_model.title,
            len(recipe_model.ingredients),
            len(recipe_model.instructions),
            recipe_model.prepTime,
            recipe_model.cookTime,
        )
        return recipe_model.model_dump()

    except (HTTPException, APIError):
        raise
    except Exception as e:
        logger.error("[FLOW] unexpected error: %s", e, exc_info=True)
        raise APIError(
            f"Error calling Gemini API: {str(e)}",
            status_code=500,
            details={"code": "UNEXPECTED", "url": url},
        )


# =====================================================================
# IMAGE → OCR → OLLAMA
# =====================================================================


@router.post("/extract_recipe_from_image")
async def extract_recipe_from_image(req: ImageExtractionRequest):
    """Extract recipe from base64 encoded image using OCR and Ollama."""
    try:
        data = req.image_data
        if "," in data:
            data = data.split(",", 1)[1]
        image_bytes = base64.b64decode(data)
        text = extract_text_from_image(image_bytes)
        if not text or len(text) < 40:
            raise HTTPException(
                status_code=400, detail="Not enough text extracted from image"
            )

        prompt = create_recipe_extraction_prompt(text)
        payload = {
            "model": MODEL_NAME,
            "prompt": prompt,
            "stream": False,
            "format": "json",
            "options": {
                "temperature": 0,
                "num_ctx": 4096,
                "top_k": 40,
                "top_p": 0.9,
            },
        }
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
            r = await client.post(OLLAMA_API_URL, json=payload)
            r.raise_for_status()
            data = r.json()
        output = data.get("response", "")

        try:
            recipe_dict = json.loads(output)
        except Exception:
            recipe_dict = await extract_and_parse_llm_json(output)

        recipe_model = normalize_recipe_fields(recipe_dict)
        return recipe_model.model_dump()

    except HTTPException:
        raise
    except Exception as e:
        logger.error("[IMG] error: %s", e, exc_info=True)
        raise HTTPException(
            status_code=500, detail=f"Error processing image: {str(e)}"
        )


@router.post("/upload_recipe_image")
async def upload_recipe_image(file: UploadFile = File(...)):
    """Upload and extract recipe from multipart image file."""
    try:
        contents = await file.read()
        text = extract_text_from_image(contents)
        if not text or len(text) < 40:
            raise HTTPException(
                status_code=400, detail="Not enough text extracted from image"
            )

        prompt = create_recipe_extraction_prompt(text)
        payload = {
            "model": MODEL_NAME,
            "prompt": prompt,
            "stream": False,
            "format": "json",
            "options": {
                "temperature": 0,
                "num_ctx": 4096,
                "top_k": 40,
                "top_p": 0.9,
            },
        }
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
            r = await client.post(OLLAMA_API_URL, json=payload)
            r.raise_for_status()
            data = r.json()
        output = data.get("response", "")

        try:
            recipe_dict = json.loads(output)
        except Exception:
            recipe_dict = await extract_and_parse_llm_json(output)
        recipe_model = normalize_recipe_fields(recipe_dict)
        return recipe_model.model_dump()

    except HTTPException:
        raise
    except Exception as e:
        logger.error("[UPLOAD] error: %s", e, exc_info=True)
        raise HTTPException(
            status_code=500, detail=f"Error processing uploaded image: {str(e)}"
        )


# =====================================================================
# TEST ZYTE RAW OUTPUT (ARTICLE MODE)
# =====================================================================

@router.get("/test_zyte")
async def test_zyte(
    url: str = "https://kerenagam.co.il/%d7%a8%d7%95%d7%9c%d7%93%d7%aa-%d7%98%d7%99%d7%a8%d7%9e%d7%99%d7%a1%d7%95-%d7%99%d7%a4%d7%99%d7%a4%d7%99%d7%99%d7%94/",
):
    """Test endpoint to fetch raw JSON from Zyte API in article mode."""
    if not ZYTE_API_KEY:
        raise HTTPException(status_code=500, detail="ZYTE_API_KEY not configured")

    payload = {
        "url": url,
        "article": True,
        "articleOptions": {"extractFrom": "httpResponseBody"},
        "followRedirect": True,
    }

    try:
        async with httpx.AsyncClient(
            timeout=HTTP_TIMEOUT, auth=(ZYTE_API_KEY, "")
        ) as client:
            resp = await client.post("https://api.zyte.com/v1/extract", json=payload)
            resp.raise_for_status()
            data = resp.json()

        logger.info("[TEST_ZYTE] Successfully fetched from Zyte (article) for url=%s", url)
        return data

    except httpx.HTTPStatusError as e:
        status_code = e.response.status_code if e.response is not None else None
        text_preview = ""
        try:
            text_preview = e.response.text[:1000] if e.response is not None else ""
        except Exception:
            pass

        logger.error(
            "[TEST_ZYTE] HTTP error: status=%s, url=%s, body=%s",
            status_code,
            url,
            text_preview or "no body",
        )
        raise HTTPException(
            status_code=502,
            detail=f"Zyte API error: HTTP {status_code}: {str(e)}",
        )
    except Exception as e:
        logger.error("[TEST_ZYTE] Error: %s, url=%s", e, url, exc_info=True)
        raise HTTPException(
            status_code=500, detail=f"Error calling Zyte API: {str(e)}"
        )


# =====================================================================
# CUSTOM RECIPE (OLLAMA)
# =====================================================================


@router.post("/custom_recipe")
async def custom_recipe(req: CustomRecipeRequest):
    """Generate custom recipe from groceries and description using Ollama."""
    try:
        prompt = create_custom_recipe_prompt(req.groceries, req.description)
        payload = {
            "model": MODEL_NAME,
            "prompt": prompt,
            "stream": False,
            "format": "json",
            "options": {
                "temperature": 0.5,
                "num_ctx": 4096,
                "top_k": 50,
                "top_p": 0.95,
            },
        }
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
            r = await client.post(OLLAMA_API_URL, json=payload)
            r.raise_for_status()
            data = r.json()
        output = data.get("response", "")

        try:
            recipe_dict = json.loads(output)
        except Exception:
            recipe_dict = await extract_and_parse_llm_json(output)
        recipe_model = normalize_recipe_fields(recipe_dict)
        return recipe_model.model_dump()

    except HTTPException:
        raise
    except Exception as e:
        logger.error("[CUSTOM] error: %s", e, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail="An unexpected error occurred during custom recipe generation",
        )
