from __future__ import annotations

import asyncio
import json
import logging
import re
from dataclasses import dataclass
from typing import Any, Dict
from urllib.parse import urlparse

from google import genai
from google.genai import types
from playwright.async_api import async_playwright, TimeoutError as PWTimeoutError

from app.config import settings
from app.models.recipe import Recipe
from app.utils.exceptions import ScrapingError

logger = logging.getLogger(__name__)

SOCIAL_DOMAINS = ("instagram.com", "tiktok.com")
GEMINI_MODEL = "gemini-2.5-flash-lite"


# =========================================================
# Utils
# =========================================================
def is_social_url(url: str) -> bool:
    domain = urlparse(url).netloc.lower()
    return any(d in domain for d in SOCIAL_DOMAINS)


def extract_first_json_object(text: str) -> str:
    text = (text or "").strip()
    if not text:
        return text

    text = re.sub(r"^```(?:json)?\s*", "", text, flags=re.IGNORECASE | re.MULTILINE)
    text = re.sub(r"\s*```\s*$", "", text, flags=re.MULTILINE).strip()

    if text.startswith("{") and text.endswith("}"):
        return text

    i = text.find("{")
    j = text.rfind("}")
    if i != -1 and j != -1 and j > i:
        return text[i : j + 1]

    return text


def clean_text(s: str) -> str:
    s = (s or "").strip()
    s = re.sub(r"\n{3,}", "\n\n", s)
    return s


# =========================================================
# Headless social extraction
# =========================================================
@dataclass
class SocialExtract:
    title: str
    caption: str
    visible_text: str


    def as_prompt_text(self) -> str:
        parts = []
        if self.title:
            parts.append(f"TITLE META:\n{self.title}")

        if self.caption:
            parts.append(f"CAPTION:\n{self.caption}")
        if self.visible_text:
            parts.append(f"VISIBLE TEXT:\n{self.visible_text}")
        return clean_text("\n\n".join(parts))


async def extract_social_text_headless(url: str, timeout_ms: int = 8000) -> SocialExtract:
    try:
        async with async_playwright() as p:
            browser = await p.chromium.launch(
                headless=True,
                args=[
                    "--no-sandbox",
                    "--disable-dev-shm-usage",
                    "--disable-gpu",
                    "--disable-software-rasterizer",
                    "--disable-extensions",
                    "--disable-background-networking",
                    "--disable-background-timer-throttling",
                    "--disable-backgrounding-occluded-windows",
                    "--disable-breakpad",
                    "--disable-component-extensions-with-background-pages",
                    "--disable-features=TranslateUI",
                    "--disable-ipc-flooding-protection",
                    "--disable-renderer-backgrounding",
                    "--disable-sync",
                    "--metrics-recording-only",
                    "--mute-audio",
                    "--no-first-run",
                    "--no-default-browser-check",
                    "--no-pings",
                    "--disable-font-subpixel-positioning",
                    "--disable-lcd-text",
                    "--font-render-hinting=none",
                ],
            )

            context = await browser.new_context(
                user_agent=(
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/123.0.0.0 Safari/537.36"
                ),
                locale="he-IL",
                viewport={"width": 800, "height": 600},  # Smaller viewport
                java_script_enabled=True,
                ignore_https_errors=True,
                # Disable fonts to prevent crashes
                extra_http_headers={"Accept-Language": "he-IL,he;q=0.9"},
            )

            page = await context.new_page()
            page.set_default_timeout(timeout_ms)
            
            # Block images, fonts, media to save memory
            async def route_handler(route):
                if route.request.resource_type in ["image", "font", "media", "stylesheet"]:
                    await route.abort()
                else:
                    await route.continue_()
            
            await page.route("**/*", route_handler)

            # Use asyncio timeout to prevent hanging
            try:
                await asyncio.wait_for(
                    page.goto(url, wait_until="domcontentloaded", timeout=5000),
                    timeout=6.0
                )
            except (PWTimeoutError, asyncio.TimeoutError):
                pass

            # Skip networkidle wait - too memory intensive, just wait a short time
            try:
                await asyncio.sleep(0.5)  # Brief wait instead of networkidle
            except Exception:
                pass

            async def get_meta(prop: str = "", name: str = "") -> str:
                try:
                    sel = f'meta[property="{prop}"]' if prop else f'meta[name="{name}"]'
                    loc = page.locator(sel)
                    count = await loc.count()
                    if count > 0:
                        return (await loc.first.get_attribute("content") or "").strip()
                except Exception:
                    pass
                return ""

            title = await get_meta(prop="og:title") or await page.title()
            
            # description removed as per request
            description = ""


            # Get visible text (simplified to avoid crashes)
            try:
                visible_text = await asyncio.wait_for(
                    page.locator("body").inner_text(timeout=2000),
                    timeout=3.0
                )
            except Exception:
                visible_text = ""

            # Get caption from meta tags first (more reliable)
            caption = description or ""
            
            # Try to get caption from page content (simplified)
            if not caption:
                try:
                    domain = urlparse(url).netloc.lower()
                    if "instagram.com" in domain:
                        # Try simple selectors
                        try:
                            loc = page.locator('article h1')
                            count = await asyncio.wait_for(loc.count(), timeout=1.0)
                            if count > 0:
                                caption = (await asyncio.wait_for(loc.first.inner_text(timeout=1000), timeout=1.5) or "").strip()
                        except Exception:
                            pass
                    else:  # TikTok
                        try:
                            loc = page.locator('[data-e2e="video-desc"]')
                            count = await asyncio.wait_for(loc.count(), timeout=1.0)
                            if count > 0:
                                caption = (await asyncio.wait_for(loc.first.inner_text(timeout=1000), timeout=1.5) or "").strip()
                        except Exception:
                            pass
                except Exception:
                    pass

            # Close browser resources with error handling
            try:
                await context.close()
            except Exception:
                pass
            try:
                await browser.close()
            except Exception:
                pass

            return SocialExtract(
                title=title or "",
                caption=caption or "",
                visible_text=visible_text or "",
            )

    except Exception as e:
        # If browser crashes, return minimal data and let fallback handle it
        logger.warning(f"Playwright browser crashed: {e}, returning minimal extract")
        return SocialExtract(
            title="",
            caption="",
            visible_text="",
        )



# =========================================================
# Scraper Service
# =========================================================
class ScraperService:
    def __init__(self):
        self._client: genai.Client | None = None

    @property
    def client(self) -> genai.Client:
        if self._client is None:
            self._client = genai.Client(api_key=settings.gemini_api_key)
        return self._client
    
    async def extract_recipe_from_url(self, url: str) -> Recipe:
        if is_social_url(url):
            logger.info(f"[social] Using headless browser for: {url}")
            return await self._extract_social(url)

        # Regular website
        try:
            logger.info(f"[url_context] Trying url_context: {url}")
            return await self._extract_with_url_context(url)
        except Exception as e:
            logger.warning(f"url_context failed: {e}, trying google_search")
            try:
                recipe = await self._extract_with_google_search(url)
                # Verify we actually got instructions
                if not recipe.instructionGroups or not recipe.instructionGroups[0].instructions:
                    logger.warning("google_search returned empty instructions, trying Playwright fallback")
                    raise ScrapingError("Empty instructions from google_search")
                return recipe
            except Exception as e2:
                logger.warning(f"google_search failed (or returned empty): {e2}, trying Playwright text extraction")
                return await self._extract_with_playwright(url)



    # -------------------------
    # Regular URLs
    # -------------------------
    async def _extract_with_url_context(self, url: str) -> Recipe:
        prompt = self._build_url_context_prompt(url)
        loop = asyncio.get_event_loop()

        response = await loop.run_in_executor(
            None,
            lambda: self.client.models.generate_content(
                model=GEMINI_MODEL,
                contents=prompt,
                config=types.GenerateContentConfig(
                    tools=[{"url_context": {}}],
                    response_mime_type="text/plain",


                    temperature=0.0,
                ),
            ),
        )

        return self._parse_recipe_response(response, url)

    async def _extract_with_google_search(self, url: str) -> Recipe:
        prompt = self._build_google_search_prompt(url)
        loop = asyncio.get_event_loop()


        response = await loop.run_in_executor(
            None,
            lambda: self.client.models.generate_content(
                model=GEMINI_MODEL,
                contents=prompt,
                config=types.GenerateContentConfig(
                    tools=[types.Tool(google_search=types.GoogleSearch())],
                    response_mime_type="text/plain",



                    temperature=0.0,
                ),
            ),
        )

        return self._parse_recipe_response(response, url)

    async def _extract_with_playwright(self, url: str) -> Recipe:

        """
        Fallback method using Playwright to extract page text rather than the `google_search` tool
        (which often returns only snippets).
        Uses a generalized version of the `extract_social_text_headless` logic (now suitable for any site).
        """
        try:
            # Reusing extract_social_text_headless as it does a generic body extraction
            # We bump timeout slightly for general sites which might be heavier
            content_data = await asyncio.wait_for(
                extract_social_text_headless(url, timeout_ms=15000),
                timeout=20.0
            )
        except Exception as e:
            logger.error(f"Fallback Playwright extraction failed: {e}")
            raise ScrapingError(f"Both url_context and fallback extraction failed for {url}") from e

        # Convert extraction to text for the prompt
        # We can reuse _build_text_prompt which takes raw text and asks for JSON
        text = content_data.as_prompt_text()
        if len(text.strip()) < 50:
             # If we got almost nothing, it's likely blocked or empty
             raise ScrapingError("Fallback extraction returned insufficient text.")

        prompt = self._build_text_prompt(url, text)

        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None,
            lambda: self.client.models.generate_content(
                model=GEMINI_MODEL,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",

                    temperature=0.0,
                ),
            ),
        )

        return self._parse_recipe_response(response, url)


    # -------------------------
    # Social URLs
    # -------------------------
    async def _extract_social(self, url: str) -> Recipe:
        # Wrap in timeout to prevent hanging
        try:
            social = await asyncio.wait_for(
                extract_social_text_headless(url),
                timeout=15.0  # Max 15 seconds for entire extraction
            )
        except asyncio.TimeoutError:
            raise ScrapingError("Social media extraction timed out after 15 seconds")
        except Exception as e:
            # If Playwright fails (browser crash, etc.), fallback to generalized extraction (which is also Playwright based, but cleaner recursion)
            # Actually, if social extract fails here, it essentially failed Playwright.
            # We can try one last ditch effort or just raise. 
            # Given we are already in _extract_social, let's just fail or try the fallback method which wraps the same logic.
            # If Playwright fails (browser crash, etc.), fallback to generalized extraction (which is also Playwright based, but cleaner recursion)
            # Actually, if social extract fails here, it essentially failed Playwright.
            # We can try one last ditch effort or just raise. 
            # Given we are already in _extract_social, let's just fail or try the fallback method which wraps the same logic.
            logger.warning(f"Playwright social extraction failed: {e}, attempting generic fallback")
            return await self._extract_with_playwright(url)


        
        text = social.as_prompt_text()

        if len(text.strip()) < 30:
            raise ScrapingError(
                "Social extraction returned insufficient text. "
                "Caption may be private or blocked."
            )

        prompt = self._build_text_prompt(url, text)

        response = self.client.models.generate_content(
            model=GEMINI_MODEL,
            contents=prompt,
            config=types.GenerateContentConfig(
                response_mime_type="text/plain",
                temperature=0.0,
            ),
        )

        return self._parse_recipe_response(response, url)

    # -------------------------
    # Parsing
    # -------------------------
    def _parse_recipe_response(self, response: Any, url: str) -> Recipe:
        if not response:
            logger.error(f"Gemini returned None response for {url}")
            raise ScrapingError("Gemini returned None response")

        # Log finish reason if available
        try:
            candidate = response.candidates[0]
            if hasattr(candidate, 'finish_reason'):
                logger.info(f"Gemini finish reason for {url}: {candidate.finish_reason}")
                
            # If text is empty/missing, log detailed candidate info
            if not response.text:
                logger.error(f"Gemini returned empty text for {url}. Candidate: {candidate}")
                # Check for safety ratings
                if hasattr(candidate, 'safety_ratings'):
                    logger.error(f"Safety ratings: {candidate.safety_ratings}")
        except Exception as e:
            logger.warning(f"Could not log detailed candidate info: {e}")

        if not response.text or not response.text.strip():
            logger.error(f"Gemini returned empty response text for {url}")
            raise ScrapingError("Gemini returned empty response")
        
        # Log raw response for debugging
        logger.info(f"Gemini Raw Text: {response.text}")



        json_text = extract_first_json_object(response.text)
        data = json.loads(json_text)
        
        # Log raw response for debugging
        logger.info(f"Gemini raw response for {url}: instructionGroups count={len(data.get('instructionGroups', []))}")
        if data.get('instructionGroups'):
            for i, group in enumerate(data.get('instructionGroups', [])):
                logger.info(f"  Group {i}: name='{group.get('name')}', instructions count={len(group.get('instructions', []))}")

        # Normalize data to match Recipe model
        data = self._normalize_recipe_data(data)
        
        data["source"] = url
        return Recipe(**data)
    
    def _normalize_recipe_data(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Normalize recipe data from Gemini to match Recipe model."""
        # Handle wrapped responses (e.g. {"Recipe": {...}} or {"recipe": {...}})
        if len(data) == 1 and isinstance(list(data.values())[0], dict):
             key = list(data.keys())[0].lower()
             inner = list(data.values())[0]
             # If strictly one key, and inner has recipe-like fields, unwrap it
             if "recipe" in key or "instructiongroups" in inner or "ingredients" in inner:
                 logger.info(f"Unwrapping nested JSON response from key: {list(data.keys())[0]}")
                 data = inner

        normalized = dict(data)

        
        # servings: convert int to string
        if "servings" in normalized and normalized["servings"] is not None:
            if isinstance(normalized["servings"], (int, float)):
                normalized["servings"] = str(int(normalized["servings"]))
            elif not isinstance(normalized["servings"], str):
                normalized["servings"] = str(normalized["servings"])
        
        # ingredients: ensure it's a list of strings (for backward compatibility)
        if "ingredients" in normalized:
            if isinstance(normalized["ingredients"], list):
                # Convert objects to strings if needed
                flat_ingredients = []
                for ing in normalized["ingredients"]:
                    if isinstance(ing, str):
                        flat_ingredients.append(ing)
                    elif isinstance(ing, dict):
                        # Convert object format to string
                        parts = []
                        if "quantity" in ing and ing["quantity"]:
                            parts.append(str(ing["quantity"]))
                        if "unit" in ing and ing["unit"]:
                            parts.append(ing["unit"])
                        if "name" in ing and ing["name"]:
                            parts.append(ing["name"])
                        flat_ingredients.append(" ".join(parts) if parts else str(ing))
                    else:
                        flat_ingredients.append(str(ing))
                normalized["ingredients"] = flat_ingredients
            else:
                normalized["ingredients"] = []
        else:
            normalized["ingredients"] = []
        
        # ingredientGroups: ensure ingredients are in correct format [{"raw": "..."}]
        if "ingredientGroups" in normalized and isinstance(normalized["ingredientGroups"], list):
            for group in normalized["ingredientGroups"]:
                if isinstance(group, dict) and "ingredients" in group:
                    if isinstance(group["ingredients"], list):
                        normalized_ingredients = []
                        for ing in group["ingredients"]:
                            if isinstance(ing, str):
                                normalized_ingredients.append({"raw": ing})
                            elif isinstance(ing, dict):
                                if "raw" in ing:
                                    normalized_ingredients.append(ing)
                                else:
                                    # Convert object format to raw string
                                    parts = []
                                    if "quantity" in ing and ing["quantity"]:
                                        parts.append(str(ing["quantity"]))
                                    if "unit" in ing and ing["unit"]:
                                        parts.append(ing["unit"])
                                    if "name" in ing and ing["name"]:
                                        parts.append(ing["name"])
                                    normalized_ingredients.append({"raw": " ".join(parts) if parts else str(ing)})
                            else:
                                normalized_ingredients.append({"raw": str(ing)})
                        group["ingredients"] = normalized_ingredients
        elif "ingredientGroups" not in normalized:
            normalized["ingredientGroups"] = []
        
        # nutrition: convert string values to numbers or None
        if "nutrition" in normalized and isinstance(normalized["nutrition"], dict):
            nutrition = normalized["nutrition"]
            for field in ["calories", "protein_g", "fat_g", "carbs_g"]:
                if field in nutrition:
                    value = nutrition[field]
                    if isinstance(value, str):
                        # Try to parse number, or set to None
                        try:
                            # Remove non-numeric characters except digits and decimal point
                            cleaned = ''.join(c for c in value if c.isdigit() or c == '.')
                            if cleaned:
                                nutrition[field] = float(cleaned)
                            else:
                                nutrition[field] = None
                        except (ValueError, TypeError):
                            nutrition[field] = None
                    elif not isinstance(value, (int, float)) and value is not None:
                        nutrition[field] = None
        
        # Ensure required fields exist
        if "ingredientGroups" not in normalized:
            normalized["ingredientGroups"] = []
        if "instructionGroups" not in normalized:
            normalized["instructionGroups"] = []
        elif isinstance(normalized["instructionGroups"], list):
            # Ensure instructionGroups is not empty - if empty, create default
            if not normalized["instructionGroups"]:
                normalized["instructionGroups"] = [{"name": "הוראות הכנה", "instructions": []}]
            # Ensure each group has instructions list
            for group in normalized["instructionGroups"]:
                if isinstance(group, dict):
                    if "instructions" not in group or not isinstance(group["instructions"], list):
                        group["instructions"] = []
                    # Ensure name exists
                    if "name" not in group or not group["name"]:
                        group["name"] = "הוראות הכנה"
        if "notes" not in normalized:
            normalized["notes"] = []
        if "images" not in normalized:
            normalized["images"] = []
        
        return normalized

    # -------------------------
    # Prompts
    # -------------------------
    def _build_url_context_prompt(self, url: str) -> str:
        schema = self._get_recipe_json_schema()
        return f"""
Use the URL itself: {url}
Extract the recipe strictly as it appears on the page.

Required JSON Structure (Schema):
{schema}

Return JSON ONLY matching exactly the above structure.

Critical Instructions:
1. **Instruction Groups (MANDATORY):**
   - Extract **ALL** instructions fully. Do not stop in the middle!
   - Look for headers like "Preparation", "Instructions", "אופן הכנה".
   - Verify that the instructions reach a logical conclusion (e.g., "Serve", "בתיאבון").
   - Split long instructions into separate sentences.

2. **Servings (Yield/Quantity):**
   - Explicitly look for a quantity/yield statement.
   - Examples to look for: "10 cookies", "4 servings", "המרכיבים ל-10".
   - **CAUTION:** Do NOT confuse with pan size (e.g., "Size 24"). If it says "Ingredients for 10" (המרכיבים ל 10), the quantity is "10" (or "10 items"). Only if no other quantity exists, mention the pan size.

3. **Notes:**
   - Look for sections like "Tips", "Notes", "Did you know?", "Points to note" (טיפים, הערות, הידעת) and extract them into the `notes` list.

4. **Ingredients:**
   - Extract **ALL** ingredients appearing on the page.

Do not translate (unless it's to English if requested, but keep original text mostly), do not normalize, do not invent.
"""


    def _build_google_search_prompt(self, url: str) -> str:
        schema = self._get_recipe_json_schema()
        return f"""
Task: Find and extract the full recipe from this URL: {url}
Use the search tool (google_search) to find the following details:

1. **Title:** Required.
2. **Servings (Yield/Quantity):**
   - Look for produced quantity (e.g., "15 cookies", "4 servings", "15 עוגיות").
   - Prefer item quantity over pan size.
3. **Ingredients:** All ingredients, no omissions.
4. **Instructions:**
   - Bring the full text of all instructions.
   - **MANDATORY:** Find the full, non-truncated text. If the text in the search result is truncated ("..."), try to find another source or the continuation on the page.
   - Do not summarize! Bring all steps until the end.
   - Verify you reached the end of the recipe (e.g., "Serve", "Bon Appetit", "בתיאבון").
5. **Notes:**
   - Search for tips, notes, and highlights (usually at the end of the recipe), e.g., "Tips", "Notes", "טיפים".

Required JSON Structure (Schema):
{schema}

Return JSON ONLY.

Critical Instructions:
- title: Do not forget!
- instructionGroups: Find the **FULL** text! Do not settle for truncated text.
- servings: be precise (e.g., "15-17 cookies").
- notes: Find tips at the end of the recipe.

Ensure instructions are complete and not truncated.
"""





    def _get_recipe_json_schema(self) -> str:
        return """
{
  "title": "string (Required)",
  "servings": "string (Required, e.g. '15 cookies'. Prefer quantity over size)",

  "prepTimeMinutes": "integer",
  "cookTimeMinutes": "integer",
  "totalTimeMinutes": "integer",
  "ingredients": ["string (flat list of all ingredients)"],
  "ingredientGroups": [
    {
      "name": "string (e.g. 'For the dough')",
      "ingredients": [{"raw": "string (full text)"}]
    }
  ],
  "instructionGroups": [
    {
      "name": "string (e.g. 'Preparation')",
      "instructions": ["string (each step as a separate string). Must be complete."]
    }
  ],
  "notes": ["string (Tips, Did you know, etc.)"],
  "nutrition": {
    "calories": "number",
    "protein_g": "number",
    "fat_g": "number",
    "carbs_g": "number"
  }
}
"""






    def _build_text_prompt(self, url: str, text: str) -> str:
        return f"""
We have text extracted from a website (or social network).

Source URL: {url}

{text}

Extract a recipe and return JSON ONLY in the Recipe format.

Important:
- instructionGroups: **MANDATORY** - Extract all instructions. Look for headers like "Instructions", "Preparation", "אופן הכנה". If instructions are in one paragraph, split them into separate sentences. Each sentence = one instruction. If no headers, put everything under "Preparation".
- servings: string, not number. Example: "4 servings", "4 מנות".
- ingredientGroups: [{{"name": null, "ingredients": [{{"raw": "Full text of ingredient"}}]}}]
- ingredients: Flat list of strings ["ingredient 1", "ingredient 2"]
- nutrition: Numbers only (not "not specified"). If unknown: null or 0.

Do not invent, do not change, nutrition information is mandatory if available.
"""

