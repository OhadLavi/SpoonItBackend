# routes/extraction.py
"""Recipe extraction endpoints for URL, image, and custom recipes."""

import base64
import json
import re
from typing import Dict, Any
from fastapi import APIRouter, HTTPException, UploadFile, File
import httpx
import requests

from config import logger, GEMINI_API_KEY, OLLAMA_API_URL, MODEL_NAME, HTTP_TIMEOUT, ZYTE_API_KEY
from errors import APIError
from models import (
    RecipeExtractionRequest,
    ImageExtractionRequest,
    CustomRecipeRequest,
    IngredientGroup,
    RecipeModel,
)
from services.gemini_service import get_gemini_model
from services.ocr_service import extract_text_from_image
from services.prompt_service import (
    create_recipe_extraction_prompt,
    create_extraction_prompt_from_url,
    create_custom_recipe_prompt,
    create_zyte_extraction_prompt,
)
from services.fetcher_service import fetch_html_content
from utils.json_repair import extract_and_parse_llm_json
from utils.normalization import normalize_recipe_fields

router = APIRouter()


async def fetch_zyte_content(url: str) -> Dict[str, Any]:
    """
    Fetch article content from Zyte API.
    
    Returns a dictionary with:
    - itemMain: main article content
    - images: list of image URLs
    - headline: article title
    - url: article URL
    """
    if not ZYTE_API_KEY:
        raise APIError(
            "ZYTE_API_KEY not configured",
            status_code=500,
            details={"code": "ZYTE_NOT_CONFIGURED"},
        )
    
    try:
        response = requests.post(
            "https://api.zyte.com/v1/extract",
            auth=(ZYTE_API_KEY, ""),
            json={
                "url": url,
                "pageContent": True,
                "pageContentOptions": {"extractFrom": "httpResponseBody"},
                "followRedirect": True,
            },
            timeout=HTTP_TIMEOUT,
        )
        response.raise_for_status()
        data = response.json()

        # Log the response structure for debugging
        logger.info("[ZYTE] Response keys: %s", list(data.keys()) if isinstance(data, dict) else "not a dict")
        
        # Get pageContent (it's a string, not a dict)
        page_content = data.get("pageContent")
        if not page_content:
            logger.error("[ZYTE] No pageContent in response for %s. Response keys: %s", url, list(data.keys()) if isinstance(data, dict) else "not a dict")
            raise APIError(
                "No page content found in Zyte response",
                status_code=502,
                details={"code": "ZYTE_NO_PAGE_CONTENT", "url": url, "response_keys": list(data.keys()) if isinstance(data, dict) else None},
            )
        
        # pageContent is a string (the extracted text content)
        if not isinstance(page_content, str):
            logger.warning("[ZYTE] pageContent is not a string: %s (type: %s), converting", type(page_content), url)
            page_content = str(page_content)
        
        logger.info("[ZYTE] Successfully extracted pageContent (%d chars) for %s", len(page_content), url)
        
        return {
            "itemMain": page_content,
            "images": data.get("images", []),
            "headline": data.get("headline", ""),
            "url": data.get("url", url),
        }

    # 1) network / HTTP / timeout errors from requests
    except requests.exceptions.HTTPError as e:
        # HTTP errors (4xx, 5xx)
        status_code = e.response.status_code if e.response else None
        response_text = ""
        try:
            if e.response:
                response_text = e.response.text[:500]  # First 500 chars
        except Exception:
            pass
        
        logger.error(
            "[ZYTE] HTTP error for %s: status=%s, response=%s",
            url,
            status_code,
            response_text[:200] if response_text else "no response body",
            exc_info=True,
        )
        
        # 520 is Cloudflare error - origin server issue
        if status_code == 520:
            raise APIError(
                "Zyte API received 520 error from origin server (site may be blocking Zyte). Try again later.",
                status_code=502,
                details={
                    "code": "ZYTE_520_ERROR",
                    "url": url,
                    "message": "Origin server returned invalid response to Zyte",
                },
            )
        
        raise APIError(
            f"Zyte API request failed with status {status_code}: {str(e)}",
            status_code=502,
            details={
                "code": "ZYTE_REQUEST_FAILED",
                "url": url,
                "http_status": status_code,
                "response_preview": response_text[:200] if response_text else None,
            },
        )
    except requests.exceptions.RequestException as e:
        logger.error("[ZYTE] Request error for %s: %s", url, e, exc_info=True)
        raise APIError(
            f"Zyte API request failed: {str(e)}",
            status_code=502,
            details={"code": "ZYTE_REQUEST_FAILED", "url": url, "error_type": type(e).__name__},
        )

    # 2) preserve any APIError we ourselves raised above
    except APIError:
        # don't wrap again, just bubble up so the message/status_code stay intact
        raise

    # 3) truly unexpected stuff
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
    Extract recipe using Zyte API fallback and Gemini for ingredients/instructions.
    
    Returns a complete RecipeModel dictionary.
    """
    logger.info("[ZYTE] Fetching content from Zyte API for url=%s", url)
    
    # Fetch article data from Zyte
    zyte_data = await fetch_zyte_content(url)
    
    item_main = zyte_data.get("itemMain", "")
    if not item_main or len(item_main.strip()) < 100:
        raise APIError(
            "Zyte returned insufficient article content",
            status_code=502,
            details={"code": "ZYTE_INSUFFICIENT_CONTENT", "url": url},
        )
    
    # Use Gemini to extract ingredients and instructions from the article content
    logger.info("[ZYTE] Extracting ingredients/instructions from Zyte content using Gemini")
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
        gemini_dict = json.loads(response_text)
    except Exception:
        try:
            gemini_dict = await extract_and_parse_llm_json(response_text)
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
    
    # Combine Zyte data with Gemini extraction
    # Get first image URL if available
    image_url = ""
    images = zyte_data.get("images", [])
    if images and isinstance(images, list) and len(images) > 0:
        # images can be a list of URLs or list of dicts with url field
        first_image = images[0]
        if isinstance(first_image, dict):
            image_url = first_image.get("url", "")
        elif isinstance(first_image, str):
            image_url = first_image
    
    # Build the complete recipe dictionary
    recipe_dict = {
        "title": zyte_data.get("headline", ""),
        "description": "",  # Can be extracted from itemMain if needed
        "ingredients": gemini_dict.get("ingredients", []),
        "ingredientsGroups": gemini_dict.get("ingredientsGroups", []),
        "instructions": gemini_dict.get("instructions", []),
        "prepTime": int(gemini_dict.get("prepTime", 0) or 0),
        "cookTime": int(gemini_dict.get("cookTime", 0) or 0),
        "servings": int(gemini_dict.get("servings", 1) or 1),
        "tags": [],
        "notes": "",
        "source": zyte_data.get("url", url),
        "imageUrl": image_url,
    }
    
    # Number instructions
    instructions = recipe_dict.get("instructions", [])
    numbered_instructions = []
    for i, instruction in enumerate(instructions, 1):
        instruction_str = str(instruction).strip()
        instruction_str = re.sub(r"^\d+[\.\)]\s*", "", instruction_str)
        numbered_instructions.append(f"{i}. {instruction_str}")
    recipe_dict["instructions"] = numbered_instructions
    
    # Parse ingredientsGroups
    ingredients_groups = None
    if "ingredientsGroups" in recipe_dict and recipe_dict["ingredientsGroups"]:
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
        instructions=numbered_instructions,
        prepTime=recipe_dict.get("prepTime", 0),
        cookTime=recipe_dict.get("cookTime", 0),
        servings=recipe_dict.get("servings", 1),
        tags=recipe_dict.get("tags", []),
        notes=recipe_dict.get("notes", ""),
        source=recipe_dict.get("source", url),
        imageUrl=recipe_dict.get("imageUrl", ""),
    )
    
    logger.info(
        "[ZYTE] done | title='%s' ings=%d steps=%d prep=%d cook=%d",
        recipe_model.title,
        len(recipe_model.ingredients),
        len(recipe_model.instructions),
        recipe_model.prepTime,
        recipe_model.cookTime,
    )
    
    return recipe_model.model_dump()


async def get_page_content(url: str) -> str:
    """
    Fetches the page content using httpx with automatic Playwright fallback.
    If 403 error occurs, falls back to Zyte API.

    This delegates to services.fetcher_service.fetch_html_content, which:
      - Uses rotating browser-like headers with httpx
      - Detects bot-block pages / too-short content
      - Falls back to Playwright (Chromium headless) for JS-heavy / blocked sites
      - Truncates to ~50KB of cleaned text

    If a 403 error occurs, falls back to Zyte API for content extraction.

    Any APIError raised here is handled by the global APIError handler in main.py.
    """
    try:
        text = await fetch_html_content(url)
        return text
    except APIError as api_err:
        # Check if it's a 403 error - use Zyte fallback
        if api_err.status_code == 403:
            logger.info("[FLOW] 403 error detected, using Zyte API fallback for url=%s", url)
            # Return a special marker to indicate Zyte fallback should be used
            # We'll handle this in the extract_recipe function
            raise APIError(
                "Page is inaccessible (403), using Zyte fallback",
                status_code=403,
                details={"code": "FETCH_FORBIDDEN_ZYTE_FALLBACK", "url": url},
            )
        # Let the global APIError handler deal with other errors
        raise
    except Exception as e:
        logger.error("Unexpected error fetching page content from %s: %s", url, e, exc_info=True)
        # Wrap in APIError so it goes through the same handler
        raise APIError(
            "Unexpected error fetching page content.",
            status_code=500,
            details={"code": "FETCH_UNEXPECTED", "url": url, "error": str(e)},
        )


def create_extraction_prompt_from_content(page_content: str, url: str) -> str:
    """Create a prompt for extracting recipe from page content (similar to standalone version)."""
    # Limit content to first 10000 chars to be safe
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
async def extract_recipe(req: RecipeExtractionRequest):
    """Extract recipe from URL using Gemini API."""
    url = req.url.strip()
    logger.info("[FLOW] extract_recipe START | url=%s", url)
    if not url.startswith("http"):
        raise HTTPException(status_code=400, detail="Invalid URL")

    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY not configured")

    try:
        # Fetch page content first (via httpx + Playwright fallback)
        logger.info("[FLOW] Fetching page content from URL: %s", url)
        try:
            page_content = await get_page_content(url)
        except APIError as api_err:
            # Check if it's a 403 error - use Zyte fallback
            if api_err.status_code == 403:
                error_code = api_err.details.get("code", "")
                # Handle both the special marker and direct FETCH_FORBIDDEN from fetcher_service
                if error_code in ("FETCH_FORBIDDEN_ZYTE_FALLBACK", "FETCH_FORBIDDEN"):
                    logger.info("[FLOW] Using Zyte API fallback for url=%s", url)
                    return await extract_recipe_from_zyte(url)
            # Re-raise other APIErrors
            raise
        
        if not page_content or len(page_content.strip()) < 100:
            logger.error("[FLOW] Failed to fetch meaningful content from url=%s", url)
            raise APIError(
                "Could not fetch or parse page content",
                status_code=502,
                details={"code": "FETCH_FAILED", "url": url},
            )

        logger.info(
            "[FLOW] Page content fetched (%d chars), sending to Gemini",
            len(page_content),
        )
        model = get_gemini_model()
        prompt = create_extraction_prompt_from_content(page_content, url)

        # Use strict generation config for exact copying
        generation_config = {
            "temperature": 0.0,  # No randomness - deterministic output
            "top_p": 0.1,        # Very low sampling diversity
            "top_k": 1,          # Only consider the most likely token
            "max_output_tokens": 8192,
            "response_mime_type": "application/json",  # Force JSON output
        }

        response = model.generate_content(prompt, generation_config=generation_config)

        response_text = (response.text or "").strip()

        if not response_text:
            logger.error("[LLM] empty response from Gemini for url=%s", url)
            raise APIError(
                "Model returned empty response",
                status_code=502,
                details={"code": "LLM_EMPTY", "url": url},
            )

        # Strip code fences (if any)
        if response_text.startswith("```"):
            lines = response_text.split("\n")
            if lines and lines[0].startswith("```"):
                lines = lines[1:]
            if lines and lines[-1].strip() == "```":
                lines = lines[:-1]
            response_text = "\n".join(lines).strip()

        # Parse JSON with repair fallback
        try:
            recipe_dict = json.loads(response_text)
        except Exception:
            try:
                recipe_dict = await extract_and_parse_llm_json(response_text)
            except Exception as e:
                logger.error("[FLOW] JSON parse error (after repair). Raw head: %r", response_text[:220])
                raise APIError(
                    f"Failed to parse JSON response from Gemini: {str(e)}",
                    status_code=500,
                    details={
                        "code": "LLM_JSON_PARSE",
                        "raw_head": response_text[:500],
                        "url": url,
                    },
                )

        if not recipe_dict.get("source"):
            recipe_dict["source"] = url

        # Number instructions (remove existing numbering first)
        instructions = recipe_dict.get("instructions", [])
        numbered_instructions = []
        for i, instruction in enumerate(instructions, 1):
            instruction_str = str(instruction).strip()
            instruction_str = re.sub(r"^\d+[\.\)]\s*", "", instruction_str)
            numbered_instructions.append(f"{i}. {instruction_str}")
        recipe_dict["instructions"] = numbered_instructions

        # ingredientsGroups (optional -> Pydantic validation)
        ingredients_groups = None
        if "ingredientsGroups" in recipe_dict and recipe_dict["ingredientsGroups"]:
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
            instructions=numbered_instructions,
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
        # Let FastAPI's default HTTPException handler or our APIError handler deal with it
        raise
    except Exception as e:
        logger.error("[FLOW] unexpected error: %s", e, exc_info=True)
        raise APIError(
            f"Error calling Gemini API: {str(e)}",
            status_code=500,
            details={"code": "UNEXPECTED", "url": url},
        )


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
            raise HTTPException(status_code=400, detail="Not enough text extracted from image")

        prompt = create_recipe_extraction_prompt(text)
        payload = {
            "model": MODEL_NAME,
            "prompt": prompt,
            "stream": False,
            "format": "json",
            "options": {"temperature": 0, "num_ctx": 4096, "top_k": 40, "top_p": 0.9},
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
        raise HTTPException(status_code=500, detail=f"Error processing image: {str(e)}")


@router.post("/upload_recipe_image")
async def upload_recipe_image(file: UploadFile = File(...)):
    """Upload and extract recipe from multipart image file."""
    try:
        contents = await file.read()
        text = extract_text_from_image(contents)
        if not text or len(text) < 40:
            raise HTTPException(status_code=400, detail="Not enough text extracted from image")

        prompt = create_recipe_extraction_prompt(text)
        payload = {
            "model": MODEL_NAME,
            "prompt": prompt,
            "stream": False,
            "format": "json",
            "options": {"temperature": 0, "num_ctx": 4096, "top_k": 40, "top_p": 0.9},
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
        raise HTTPException(status_code=500, detail=f"Error processing uploaded image: {str(e)}")


@router.get("/test_zyte")
async def test_zyte(url: str = "https://kerenagam.co.il/%d7%a8%d7%95%d7%9c%d7%93%d7%aa-%d7%98%d7%99%d7%a8%d7%9e%d7%99%d7%a1%d7%95-%d7%99%d7%a4%d7%99%d7%a4%d7%99%d7%99%d7%94/"):
    """Test endpoint to fetch raw JSON from Zyte API using httpResponseBody."""
    if not ZYTE_API_KEY:
        raise HTTPException(status_code=500, detail="ZYTE_API_KEY not configured")
    
    try:
        api_response = requests.post(
            "https://api.zyte.com/v1/extract",
            auth=(ZYTE_API_KEY, ""),
            json={
                "url": url,
                "pageContent": True,
                "pageContentOptions": {"extractFrom":"httpResponseBody"},
                "followRedirect": True,
            },
            timeout=HTTP_TIMEOUT,
        )
        api_response.raise_for_status()
        data = api_response.json()
        
        logger.info("[TEST_ZYTE] Successfully fetched from Zyte for url=%s", url)
        return data
    except requests.exceptions.HTTPError as e:
        status_code = e.response.status_code if e.response else None
        response_text = ""
        try:
            if e.response:
                response_text = e.response.text[:1000]
        except Exception:
            pass
        
        logger.error("[TEST_ZYTE] HTTP error: status=%s, url=%s", status_code, url)
        raise HTTPException(
            status_code=502,
            detail=f"Zyte API error: HTTP {status_code}: {str(e)}",
        )
    except Exception as e:
        logger.error("[TEST_ZYTE] Error: %s, url=%s", e, url, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Error calling Zyte API: {str(e)}",
        )


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
            "options": {"temperature": 0.5, "num_ctx": 4096, "top_k": 50, "top_p": 0.95},
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
