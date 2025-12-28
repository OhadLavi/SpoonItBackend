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
    description: str
    caption: str
    visible_text: str

    def as_prompt_text(self) -> str:
        parts = []
        if self.title:
            parts.append(f"TITLE META:\n{self.title}")
        if self.description:
            parts.append(f"DESCRIPTION META:\n{self.description}")
        if self.caption:
            parts.append(f"CAPTION:\n{self.caption}")
        if self.visible_text:
            parts.append(f"VISIBLE TEXT:\n{self.visible_text}")
        return clean_text("\n\n".join(parts))


async def extract_social_text_headless(url: str, timeout_ms: int = 8000) -> SocialExtract:
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
                "--no-zygote",
                "--single-process",  # Reduces memory by running in single process
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
        )

        page = await context.new_page()
        page.set_default_timeout(5000)  # Reduced timeout
        
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
        description = await get_meta(prop="og:description") or await get_meta(name="description")

        try:
            visible_text = await page.locator("body").inner_text(timeout=3000)
        except Exception:
            visible_text = ""

        caption_candidates: list[str] = []
        domain = urlparse(url).netloc.lower()

        if "instagram.com" in domain:
            selectors = [
                'article h1',
                'article span',
                'meta[property="og:description"]',
            ]
        else:  # TikTok
            selectors = [
                '[data-e2e="video-desc"]',
                'h1',
                'meta[property="og:description"]',
            ]

        for sel in selectors:
            try:
                loc = page.locator(sel)
                count = await loc.count()
                if count > 0:
                    t = (await loc.first.inner_text(timeout=1500) or "").strip()
                    if t:
                        caption_candidates.append(t)
            except Exception:
                continue

        caption = caption_candidates[0] if caption_candidates else ""

        await context.close()
        await browser.close()

        return SocialExtract(
            title=title or "",
            description=description or "",
            caption=caption or "",
            visible_text=visible_text or "",
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
            return await self._extract_with_google_search(url)

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
        prompt = self._build_url_context_prompt(url)
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
        if not response or not response.text or not response.text.strip():
            raise ScrapingError("Gemini returned empty response")

        json_text = extract_first_json_object(response.text)
        data = json.loads(json_text)

        # Normalize data to match Recipe model
        data = self._normalize_recipe_data(data)
        
        data["source"] = url
        return Recipe(**data)
    
    def _normalize_recipe_data(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Normalize recipe data from Gemini to match Recipe model."""
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
        if "notes" not in normalized:
            normalized["notes"] = []
        if "images" not in normalized:
            normalized["images"] = []
        
        return normalized

    # -------------------------
    # Prompts
    # -------------------------
    def _build_url_context_prompt(self, url: str) -> str:
        return f"""
השתמש ב-URL עצמו: {url}
חלץ את המתכון בדיוק כפי שמופיע בעמוד.
החזר JSON בלבד בתבנית Recipe.

חשוב - פורמט:
- servings: מחרוזת (string), לא מספר. דוגמה: "4 מנות" או "2"
- ingredientGroups: [{{"name": null, "ingredients": [{{"raw": "טקסט מלא של המרכיב"}}]}}]
- ingredients: רשימה שטוחה של מחרוזות ["מרכיב 1", "מרכיב 2"]
- nutrition: מספרים בלבד (לא "לא צוין"). אם לא ידוע: null או 0

אל תתרגם, אל תנרמל, אל תמציא.
"""

    def _build_text_prompt(self, url: str, text: str) -> str:
        return f"""
יש לנו טקסט שחולץ מפוסט חברתי.
URL מקור: {url}

{text}

חלץ מתכון והחזר JSON בלבד בתבנית Recipe.

חשוב - פורמט:
- servings: מחרוזת (string), לא מספר. דוגמה: "4 מנות" או "2"
- ingredientGroups: [{{"name": null, "ingredients": [{{"raw": "טקסט מלא של המרכיב"}}]}}]
- ingredients: רשימה שטוחה של מחרוזות ["מרכיב 1", "מרכיב 2"]
- nutrition: מספרים בלבד (לא "לא צוין"). אם לא ידוע: null או 0

אל תמציא, אל תשנה, nutrition חובה.
"""
