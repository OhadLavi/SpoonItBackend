from __future__ import annotations

import asyncio
import json
import logging
import re
import time
from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple
from urllib.parse import urlparse

import requests
from bs4 import BeautifulSoup
from google import genai
from google.genai import types
from markdownify import markdownify
from playwright.async_api import async_playwright, TimeoutError as PWTimeoutError

from app.config import settings
from app.models.recipe import Recipe
from app.utils.exceptions import ScrapingError

logger = logging.getLogger(__name__)

SOCIAL_DOMAINS = ("instagram.com", "tiktok.com")
GEMINI_MODEL = "gemini-2.5-flash-lite"
BRIGHTDATA_API_URL = "https://api.brightdata.com/request"


# =========================================================
# Utils
# =========================================================
def find_main_content(soup: BeautifulSoup, selector: Optional[str] = None) -> Tuple[Any, str]:
    """
    Find the main content element in the HTML.
    If selector is provided, use it. Otherwise, try common selectors.
    Returns the element and the selector used.
    """
    # If selector is provided, try it first
    if selector:
        element = soup.select_one(selector)
        if element:
            return element, selector
    
    # Common selectors to try (in order of preference)
    common_selectors = [
        "main",
        "article",
        "[role='main']",
        ".content",
        "#content",
        ".main-content",
        "#main-content",
        ".post-content",
        ".entry-content",
        ".recipe-content",
        "#recipe",
        ".article-content",
        "body > div.container",
        "body > div.wrapper > div.content",
    ]
    
    # Try common selectors
    for sel in common_selectors:
        element = soup.select_one(sel)
        if element:
            # Check if element has substantial content (more than just a few words)
            text_content = element.get_text(strip=True)
            if len(text_content) > 100:  # At least 100 characters
                return element, sel
    
    # Fallback: try to find the largest text-containing div
    all_divs = soup.find_all(['div', 'section', 'article', 'main'])
    best_element = None
    max_text_length = 0
    
    for div in all_divs:
        text = div.get_text(strip=True)
        # Skip navigation, header, footer, sidebar
        classes = div.get('class', [])
        id_attr = div.get('id', '')
        skip_keywords = ['nav', 'header', 'footer', 'sidebar', 'menu', 'widget']
        
        if any(keyword in str(classes).lower() or keyword in id_attr.lower() for keyword in skip_keywords):
            continue
        
        if len(text) > max_text_length:
            max_text_length = len(text)
            best_element = div
    
    if best_element and max_text_length > 200:
        return best_element, "auto-detected (largest content block)"
    
    # Last resort: use body
    body = soup.find('body')
    if body:
        return body, "body (fallback)"
    
    # Ultimate fallback: entire document
    return soup, "entire document (fallback)"
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

        # Regular website - use BrightData API approach
        logger.info(f"[brightdata] Extracting recipe from: {url}")
        return await self._extract_with_brightdata(url)



    # -------------------------
    # Regular URLs - BrightData API Approach
    # -------------------------
    async def _extract_with_brightdata(self, url: str) -> Recipe:
        """
        Extract recipe using BrightData API to fetch HTML, parse to markdown,
        and send to Gemini with recipe schema.
        """
        start_time = time.time()
        timings = {}
        
        # STEP 1: Fetch HTML using BrightData API
        logger.info(f"Step 1: Fetching HTML from BrightData API for: {url}")
        fetch_start = time.time()
        
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {settings.brightdata_api_key}"
        }
        
        payload = {
            "zone": "spoonit_unlocker_api",
            "url": url,
            "format": "raw"
        }
        
        brightdata_start = time.time()
        try:
            response = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: requests.post(BRIGHTDATA_API_URL, json=payload, headers=headers, timeout=30)
            )
            response.raise_for_status()
        except Exception as e:
            logger.error(f"BrightData API request failed: {e}")
            raise ScrapingError(f"Failed to fetch HTML from BrightData API: {e}") from e
        
        timings["brightdata_api"] = time.time() - brightdata_start
        timings["html_fetch"] = time.time() - fetch_start
        logger.info(f"BrightData API Time: {timings['brightdata_api']:.2f} seconds")
        logger.info(f"Total HTML Fetch Time: {timings['html_fetch']:.2f} seconds")
        
        # STEP 2: Parse HTML and convert to Markdown
        logger.info("Step 2: Parsing HTML and converting to Markdown")
        parse_start = time.time()
        
        soup = BeautifulSoup(response.content, "html.parser")
        
        # Find main content (auto-detect)
        main_element, used_selector = find_main_content(soup, None)
        logger.info(f"Content selector used: {used_selector}")
        
        if main_element is None:
            logger.warning("Could not find main content element, using entire body")
            main_element = soup.find('body') or soup
        
        main_html = str(main_element)
        main_markdown = markdownify(main_html)
        
        timings["html_parse"] = time.time() - parse_start
        logger.info(f"Time to parse HTML and convert to Markdown: {timings['html_parse']:.2f} seconds")
        
        # STEP 3: Extract recipe data using Gemini API
        logger.info("Step 3: Extracting recipe data with Gemini API")
        gemini_start = time.time()
        
        prompt = self._build_markdown_extraction_prompt(url, main_markdown)
        response_schema = self._get_recipe_response_schema()
        
        loop = asyncio.get_event_loop()
        try:
            gemini_response = await loop.run_in_executor(
                None,
                lambda: self.client.models.generate_content(
                    model=GEMINI_MODEL,
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                        response_schema=response_schema,
                        temperature=0.0,
                    ),
                ),
            )
        except Exception as e:
            logger.error(f"Gemini API extraction failed: {e}")
            raise ScrapingError(f"Failed to extract recipe with Gemini: {e}") from e
        
        timings["gemini_api"] = time.time() - gemini_start
        logger.info(f"Time for Gemini API extraction: {timings['gemini_api']:.2f} seconds")
        
        # STEP 4: Parse JSON response
        logger.info("Step 4: Parsing JSON response")
        parse_json_start = time.time()
        
        if not gemini_response or not gemini_response.text:
            logger.error("Gemini returned empty response")
            raise ScrapingError("Gemini returned empty response")
        
        recipe_raw_string = gemini_response.text.strip()
        
        # Try to extract JSON if wrapped in markdown code blocks
        json_text = extract_first_json_object(recipe_raw_string)
        
        try:
            recipe_data = json.loads(json_text)
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse JSON from Gemini response: {e}")
            logger.error(f"Raw response text: {recipe_raw_string[:500]}...")  # Log first 500 chars
            raise ScrapingError(f"Failed to parse recipe JSON: {e}") from e
        
        timings["json_parse"] = time.time() - parse_json_start
        logger.info(f"Time for JSON parsing: {timings['json_parse']:.4f} seconds")
        
        # STEP 5: Calculate total time and log summary
        timings["total"] = time.time() - start_time
        
        logger.info("="*60)
        logger.info("TIMING SUMMARY:")
        logger.info("="*60)
        logger.info(f"BrightData API Time: {timings['brightdata_api']:.2f} seconds")
        logger.info(f"Total HTML Fetch Time: {timings['html_fetch']:.2f} seconds")
        logger.info(f"HTML Parse & Markdown Conversion Time: {timings['html_parse']:.2f} seconds")
        logger.info(f"Gemini API Extraction Time: {timings['gemini_api']:.2f} seconds")
        logger.info(f"JSON Parsing Time: {timings['json_parse']:.4f} seconds")
        logger.info(f"Total Time: {timings['total']:.2f} seconds")
        logger.info("="*60)
        
        # Normalize data to match Recipe model
        recipe_data = self._normalize_recipe_data(recipe_data)
        recipe_data["source"] = url
        
        return Recipe(**recipe_data)


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
            logger.error(f"Playwright social extraction failed: {e}")
            raise ScrapingError(f"Social media extraction failed: {e}") from e


        
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

        # Initialize response_text
        response_text = None
        
        # Log finish reason if available and try to get text
        try:
            candidate = response.candidates[0] if response.candidates else None
            if candidate:
                if hasattr(candidate, 'finish_reason'):
                    logger.info(f"Gemini finish reason for {url}: {candidate.finish_reason}")
                
                # Try to get text from different locations
                response_text = getattr(response, 'text', None)
                
                # If response.text is empty, try candidate.content.parts
                if not response_text and hasattr(candidate, 'content') and candidate.content:
                    if hasattr(candidate.content, 'parts') and candidate.content.parts:
                        # Try to get text from parts
                        text_parts = []
                        for part in candidate.content.parts:
                            if hasattr(part, 'text') and part.text:
                                text_parts.append(part.text)
                        if text_parts:
                            response_text = '\n'.join(text_parts)
                            logger.info(f"Gemini text found in candidate.content.parts for {url}")
                
                # Log the actual response text (even if empty)
                if response_text:
                    logger.info(f"=== GEMINI RESPONSE TEXT FOR {url} ===")
                    logger.info(response_text)
                    logger.info(f"=== END GEMINI RESPONSE TEXT ===")
                else:
                    # If text is empty/missing, log detailed candidate info
                    logger.error(f"Gemini returned empty text for {url}")
                    logger.error(f"Candidate: {candidate}")
                    # Log full candidate structure
                    logger.error(f"Full candidate structure: {repr(candidate)}")
                    if hasattr(candidate, 'content'):
                        logger.error(f"Candidate content: {repr(candidate.content)}")
                        if hasattr(candidate.content, 'parts'):
                            logger.error(f"Candidate content parts: {repr(candidate.content.parts)}")
                            # Try to log each part individually
                            for i, part in enumerate(candidate.content.parts):
                                logger.error(f"  Part {i}: {repr(part)}")
                    # Check for safety ratings
                    if hasattr(candidate, 'safety_ratings'):
                        logger.error(f"Safety ratings: {candidate.safety_ratings}")
        except Exception as e:
            logger.warning(f"Could not log detailed candidate info: {e}")
            import traceback
            logger.warning(f"Traceback: {traceback.format_exc()}")

        # Also log raw response object for debugging
        try:
            logger.info(f"=== GEMINI RAW RESPONSE OBJECT FOR {url} ===")
            logger.info(f"Response type: {type(response)}")
            logger.info(f"Response.text: {getattr(response, 'text', 'N/A')}")
            logger.info(f"Response.candidates count: {len(response.candidates) if hasattr(response, 'candidates') else 'N/A'}")
            logger.info(f"=== END GEMINI RAW RESPONSE OBJECT ===")
        except Exception as e:
            logger.warning(f"Could not log raw response object: {e}")

        # Use the text we found (either from response.text or from parts)
        if not response_text or not response_text.strip():
            logger.error(f"Gemini returned empty response text for {url}")
            raise ScrapingError("Gemini returned empty response")
        
        # Store the text back in response.text for compatibility with rest of code
        if not getattr(response, 'text', None):
            response.text = response_text



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
        
        # ingredientGroups: normalize to new structured format, preserve if already structured
        if "ingredientGroups" in normalized and isinstance(normalized["ingredientGroups"], list):
            for group in normalized["ingredientGroups"]:
                if isinstance(group, dict) and "ingredients" in group:
                    if isinstance(group["ingredients"], list):
                        normalized_ingredients = []
                        for ing in group["ingredients"]:
                            if isinstance(ing, str):
                                # String format: convert to structured with raw
                                normalized_ingredients.append({"name": ing, "raw": ing})
                            elif isinstance(ing, dict):
                                # Already an object - preserve structured format if it has 'name'
                                if "name" in ing:
                                    # New structured format - ensure it has required fields
                                    normalized_ing = {
                                        "name": ing.get("name", ""),
                                        "quantity": ing.get("quantity"),
                                        "unit": ing.get("unit"),
                                        "preparation": ing.get("preparation"),
                                        "raw": ing.get("raw")
                                    }
                                    normalized_ingredients.append(normalized_ing)
                                elif "raw" in ing:
                                    # Old format with just raw - keep it for backward compatibility
                                    normalized_ingredients.append(ing)
                                else:
                                    # Unknown format - convert to raw
                                    normalized_ingredients.append({"raw": str(ing)})
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
    def _build_markdown_extraction_prompt(self, url: str, markdown_content: str) -> str:
        """Build prompt for extracting recipe from markdown content."""
        return f"""Extract recipe data from the content below. Respond with JSON matching the provided schema.

Source URL: {url}

CONTENT:
{markdown_content}

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





    def _get_recipe_response_schema(self) -> Dict[str, Any]:
        """Get the recipe JSON schema from Pydantic model for Gemini responseSchema."""
        # Get the JSON schema from the Recipe Pydantic model
        schema = Recipe.model_json_schema()
        
        # Convert to the format expected by Gemini's responseSchema
        # Remove Pydantic-specific fields and simplify
        def clean_schema(s: Dict[str, Any]) -> Dict[str, Any]:
            """Clean Pydantic JSON schema for Gemini responseSchema format."""
            result: Dict[str, Any] = {}
            
            # Copy type
            if "type" in s:
                result["type"] = s["type"]
            
            # Handle properties
            if "properties" in s:
                result["properties"] = {}
                for key, value in s["properties"].items():
                    if isinstance(value, dict):
                        cleaned = clean_schema(value)
                        # Remove Pydantic-specific fields
                        cleaned.pop("title", None)
                        cleaned.pop("description", None)
                        result["properties"][key] = cleaned
                    else:
                        result["properties"][key] = value
            
            # Handle items (for arrays)
            if "items" in s:
                if isinstance(s["items"], dict):
                    result["items"] = clean_schema(s["items"])
                else:
                    result["items"] = s["items"]
            
            # Handle anyOf/oneOf for Optional fields
            if "anyOf" in s:
                # Find the non-null type and use it
                for option in s["anyOf"]:
                    if isinstance(option, dict) and option.get("type") != "null":
                        cleaned = clean_schema(option)
                        result.update(cleaned)
                        break
                # If we didn't find a non-null type, just use the first option
                if "type" not in result and s["anyOf"]:
                    if isinstance(s["anyOf"][0], dict):
                        result.update(clean_schema(s["anyOf"][0]))
            
            # Copy required fields (but filter out optional ones)
            if "required" in s:
                result["required"] = s["required"]
            
            return result
        
        cleaned = clean_schema(schema)
        # Remove top-level Pydantic metadata
        cleaned.pop("title", None)
        cleaned.pop("description", None)
        cleaned.pop("$defs", None)
        
        return cleaned






    def _build_text_prompt(self, url: str, text: str) -> str:
        return f"""
We have text extracted from a website (or social network).

Source URL: {url}

{text}

Extract a recipe and return JSON ONLY in the Recipe format.

Important:
- instructionGroups: **MANDATORY** - Extract all instructions. Look for headers like "Instructions", "Preparation", "אופן הכנה". If instructions are in one paragraph, split them into separate sentences. Each sentence = one instruction. If no headers, put everything under "Preparation".
- servings: string, not number. Example: "4 servings", "4 מנות".
- ingredientGroups: [{{"name": null, "ingredients": [{{"quantity": "amount or null", "name": "ingredient name (required)", "unit": "unit of measurement or null", "preparation": "preparation notes or null", "raw": "original text or null"}}]}}]
- ingredients: Flat list of strings ["ingredient 1", "ingredient 2"]
- nutrition: Numbers only (not "not specified"). If unknown: null or 0.

Do not invent, do not change, nutrition information is mandatory if available.
"""

