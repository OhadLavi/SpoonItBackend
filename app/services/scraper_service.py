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
from playwright.sync_api import sync_playwright, TimeoutError as PWTimeoutError

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


def extract_social_text_headless(url: str, timeout_ms: int = 15000) -> SocialExtract:
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=["--no-sandbox", "--disable-dev-shm-usage"],
        )

        context = browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/123.0.0.0 Safari/537.36"
            ),
            locale="he-IL",
            viewport={"width": 1280, "height": 720},
        )

        page = context.new_page()
        page.set_default_timeout(timeout_ms)

        try:
            page.goto(url, wait_until="domcontentloaded", timeout=timeout_ms)
        except PWTimeoutError:
            pass

        try:
            page.wait_for_load_state("networkidle", timeout=5000)
        except Exception:
            pass

        def get_meta(prop: str = "", name: str = "") -> str:
            try:
                sel = f'meta[property="{prop}"]' if prop else f'meta[name="{name}"]'
                loc = page.locator(sel)
                if loc.count() > 0:
                    return (loc.first.get_attribute("content") or "").strip()
            except Exception:
                pass
            return ""

        title = get_meta(prop="og:title") or page.title()
        description = get_meta(prop="og:description") or get_meta(name="description")

        try:
            visible_text = page.locator("body").inner_text(timeout=3000)
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
                if loc.count() > 0:
                    t = (loc.first.inner_text(timeout=1500) or "").strip()
                    if t:
                        caption_candidates.append(t)
            except Exception:
                continue

        caption = caption_candidates[0] if caption_candidates else ""

        context.close()
        browser.close()

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
        social = extract_social_text_headless(url)
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

        data["source"] = url
        return Recipe(**data)

    # -------------------------
    # Prompts
    # -------------------------
    def _build_url_context_prompt(self, url: str) -> str:
        return f"""
השתמש ב-URL עצמו: {url}
חלץ את המתכון בדיוק כפי שמופיע בעמוד.
החזר JSON בלבד בתבנית Recipe.
אל תתרגם, אל תנרמל, אל תמציא.
"""

    def _build_text_prompt(self, url: str, text: str) -> str:
        return f"""
יש לנו טקסט שחולץ מפוסט חברתי.
URL מקור: {url}

{text}

חלץ מתכון והחזר JSON בלבד בתבנית Recipe.
אל תמציא, אל תשנה, nutrition חובה.
"""
