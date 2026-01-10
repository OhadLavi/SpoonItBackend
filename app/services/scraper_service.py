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

try:
    import trafilatura
    _TRAFILATURA_AVAILABLE = True
except ImportError:
    _TRAFILATURA_AVAILABLE = False

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
    
    def _clean_schema_for_gemini(self, schema: Dict[str, Any]) -> Dict[str, Any]:
        """
        Remove fields that Gemini API doesn't accept in response_schema.
        Specifically removes 'additionalProperties' and 'additional_properties'.
        """
        if not isinstance(schema, dict):
            return schema
        
        cleaned = {}
        for key, value in schema.items():
            # Skip additionalProperties fields
            if key in ("additionalProperties", "additional_properties"):
                continue
            
            # Recursively clean nested dictionaries
            if isinstance(value, dict):
                cleaned[key] = self._clean_schema_for_gemini(value)
            elif isinstance(value, list):
                cleaned[key] = [
                    self._clean_schema_for_gemini(item) if isinstance(item, dict) else item
                    for item in value
                ]
            else:
                cleaned[key] = value
        
        return cleaned
    
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
        
        # Log response details
        logger.info(f"BrightData response status code: {response.status_code}")
        logger.info(f"BrightData response headers: {dict(response.headers)}")
        logger.info(f"BrightData response size: {len(response.content)} bytes")
        
        # Validate response content
        if not response.content:
            logger.error("BrightData API returned empty response content")
            raise ScrapingError("BrightData API returned empty HTML content")
        
        # Log response content (first 2000 chars for debugging)
        try:
            response_preview = response.content[:2000].decode('utf-8', errors='replace')
            logger.info(f"BrightData response preview (first 2000 chars):\n{response_preview}")
        except Exception as e:
            logger.warning(f"Could not decode response preview: {e}")
            logger.info(f"BrightData response preview (first 500 bytes, raw): {response.content[:500]}")
        
        # Log full response if it's small enough (less than 10KB)
        if len(response.content) < 10000:
            try:
                full_response = response.content.decode('utf-8', errors='replace')
                logger.info(f"BrightData full response ({len(full_response)} chars):\n{full_response}")
            except Exception as e:
                logger.warning(f"Could not decode full response: {e}")
                logger.info(f"BrightData full response (raw bytes): {response.content}")
        
        # STEP 2: Extract main content using Trafilatura (fast, article-only)
        logger.info("Step 2: Extracting main content with Trafilatura")
        parse_start = time.time()
        
        # Try to decode HTML content
        try:
            html_content = response.content.decode('utf-8', errors='replace')
            logger.info(f"Decoded HTML content length: {len(html_content)} characters")
            if len(html_content.strip()) < 100:
                logger.warning(f"HTML content is very short ({len(html_content)} chars), might be empty or error page")
                logger.debug(f"HTML content preview: {html_content[:1000]}")
        except Exception as e:
            logger.error(f"Failed to decode HTML content: {e}")
            raise ScrapingError(f"Failed to decode HTML content from BrightData: {e}") from e
        
        # Use Trafilatura for fast, article-only extraction
        main_markdown = None
        if _TRAFILATURA_AVAILABLE:
            try:
                extracted_text = trafilatura.extract(
                    html_content,
                    include_comments=False,
                    include_tables=False,
                    favor_recall=False  # Fast mode - article only
                )
                if extracted_text and len(extracted_text.strip()) > 100:
                    main_markdown = extracted_text
                    logger.info(f"Trafilatura extracted {len(main_markdown)} characters")
                else:
                    logger.warning(f"Trafilatura returned empty/too short content (length: {len(extracted_text) if extracted_text else 0}), falling back to BeautifulSoup")
            except Exception as e:
                logger.warning(f"Trafilatura extraction failed: {e}, falling back to BeautifulSoup")
        
        # Fallback to BeautifulSoup if Trafilatura didn't work
        if not main_markdown or len(main_markdown.strip()) < 100:
            logger.info("Using BeautifulSoup for content extraction")
            
            # Validate HTML content before parsing
            if not html_content or len(html_content.strip()) < 50:
                logger.error(f"HTML content is too short or empty: {len(html_content) if html_content else 0} characters")
                logger.error(f"HTML content preview: {html_content[:500] if html_content else 'None'}")
                raise ScrapingError(f"HTML content from BrightData is empty or too short ({len(html_content) if html_content else 0} chars). Response might be an error page or blocked.")
            
            try:
                soup = BeautifulSoup(html_content, "html.parser")
                
                # Check if soup parsed successfully
                if not soup:
                    logger.error("BeautifulSoup failed to parse HTML - soup is None")
                    raise ScrapingError("Failed to parse HTML with BeautifulSoup")
                
                # Try to find main content
                main_element, used_selector = find_main_content(soup, None)
                logger.info(f"Content selector used: {used_selector}")
                
                if main_element is None:
                    logger.warning("Could not find main content element, using entire body")
                    main_element = soup.find('body') or soup
                
                # If still None, use the entire soup
                if main_element is None:
                    logger.warning("No body element found, using entire soup")
                    main_element = soup
                
                # Try markdownify first
                main_html = str(main_element)
                main_markdown = markdownify(main_html)
                logger.info(f"BeautifulSoup markdownify extracted {len(main_markdown)} characters")
                
                # If markdownify resulted in empty content, try direct text extraction
                if not main_markdown or len(main_markdown.strip()) < 50:
                    logger.warning("Markdown conversion resulted in empty content, trying direct text extraction")
                    main_markdown = main_element.get_text(separator='\n', strip=True)
                    logger.info(f"BeautifulSoup direct text extraction got {len(main_markdown)} characters")
                    
                    # If still empty, log the HTML structure for debugging
                    if not main_markdown or len(main_markdown.strip()) < 50:
                        logger.error(f"Both markdownify and text extraction failed. HTML element preview: {main_html[:500]}")
                        logger.error(f"Element type: {type(main_element)}, has text: {bool(main_element.get_text()) if hasattr(main_element, 'get_text') else 'N/A'}")
                        raise ScrapingError(f"Failed to extract any text content from HTML. Element appears to be empty.")
                    
            except Exception as e:
                logger.error(f"BeautifulSoup parsing/extraction failed: {e}", exc_info=True)
                raise ScrapingError(f"Failed to extract content from HTML: {e}") from e
        
        # Validate we have content
        if not main_markdown or len(main_markdown.strip()) < 50:
            logger.error(f"Content extraction failed - only got {len(main_markdown) if main_markdown else 0} characters")
            raise ScrapingError("Failed to extract meaningful content from the page")
        
        # Limit content size to avoid sending too much to Gemini
        if len(main_markdown) > 50000:
            logger.warning(f"Content too long ({len(main_markdown)} chars), truncating to 50000")
            main_markdown = main_markdown[:50000] + "\n\n[... content truncated ...]"
        
        timings["html_parse"] = time.time() - parse_start
        logger.info(f"Time to extract content: {timings['html_parse']:.2f} seconds")
        logger.info(f"Final content length: {len(main_markdown)} characters")
        logger.debug(f"Content preview (first 500 chars): {main_markdown[:500]}")
        
        # Extract website title from HTML and prepend to content
        page_title = None
        try:
            # Parse HTML to extract title
            soup = BeautifulSoup(html_content, "html.parser")
            title_tag = soup.find('title')
            if title_tag:
                page_title = title_tag.get_text(strip=True)
                logger.info(f"Extracted page title: {page_title}")
            else:
                # Try og:title or other meta tags
                og_title = soup.find('meta', property='og:title')
                if og_title and og_title.get('content'):
                    page_title = og_title.get('content').strip()
                    logger.info(f"Extracted page title from og:title: {page_title}")
        except Exception as e:
            logger.warning(f"Failed to extract page title: {e}")
        
        # Prepend title to content if available
        if page_title:
            main_markdown = f"Page Title: {page_title}\n\n{main_markdown}"
            logger.info(f"Added title to content. New content length: {len(main_markdown)} characters")
        
        # STEP 3: Extract recipe data using Gemini API
        logger.info("Step 3: Extracting recipe data with Gemini API")
        gemini_start = time.time()
        
        # Validate content before sending to Gemini
        if not main_markdown or not main_markdown.strip():
            logger.error(f"Content validation failed: main_markdown is {type(main_markdown)}, length: {len(main_markdown) if main_markdown else 0}")
            raise ScrapingError("No content extracted from the page - cannot extract recipe")
        
        # Detect language (default to Hebrew for Hebrew sites)
        language = "he"  # Can be enhanced with actual detection if needed
        
        logger.info(f"Building prompt with content length: {len(main_markdown)} characters")
        logger.info(f"Content preview (first 200 chars): {main_markdown[:200]}")
        prompt = self._build_markdown_extraction_prompt(url, main_markdown, language)
        
        # Verify the prompt contains the content
        if "CONTENT:" in prompt and len(prompt.split("CONTENT:")[1].strip()) < 10:
            logger.error(f"WARNING: Prompt built but CONTENT section appears empty! Prompt length: {len(prompt)}")
            logger.error(f"main_markdown type: {type(main_markdown)}, length: {len(main_markdown) if main_markdown else 0}")
        
        # Log a preview of what's being sent (first 1000 chars of prompt)
        logger.debug(f"Full prompt preview (first 1000 chars): {prompt[:1000]}")
        response_schema = self._get_recipe_response_schema()
        
        # Clean schema to remove additionalProperties (Gemini doesn't accept this field)
        cleaned_schema = self._clean_schema_for_gemini(response_schema)
        
        config = types.GenerateContentConfig(
            temperature=0.0,
            top_p=0.0,  # Deterministic output
            response_mime_type="application/json",
            response_schema=cleaned_schema,
        )
        
        logger.info(f"Sending to Gemini (_extract_with_brightdata):")
        logger.info(f"  Model: {GEMINI_MODEL}")
        logger.info(f"  Prompt: {prompt}")
        logger.info(f"  Config: temperature={config.temperature}, top_p={config.top_p}, response_mime_type={config.response_mime_type}")
        logger.info(f"  Response schema: {json.dumps(cleaned_schema, indent=2, ensure_ascii=False)}")
        
        loop = asyncio.get_event_loop()
        try:
            gemini_response = await loop.run_in_executor(
                None,
                lambda: self.client.models.generate_content(
                    model=GEMINI_MODEL,
                    contents=prompt,
                    config=config,
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
        
        # Remove ingredients field before creating Recipe (it's computed, not stored)
        recipe_data.pop("ingredients", None)
        
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

        config = types.GenerateContentConfig(
            response_mime_type="text/plain",
            temperature=0.0,
        )
        
        logger.info(f"Sending to Gemini (_extract_social):")
        logger.info(f"  Model: {GEMINI_MODEL}")
        logger.info(f"  Prompt: {prompt}")
        logger.info(f"  Config: temperature={config.temperature}, response_mime_type={config.response_mime_type}")

        response = self.client.models.generate_content(
            model=GEMINI_MODEL,
            contents=prompt,
            config=config,
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
        # Remove ingredients field before creating Recipe (it's computed, not stored)
        data.pop("ingredients", None)
        
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

        
        # servings: normalize to Servings object structure
        if "servings" in normalized:
            servings = normalized["servings"]
            if isinstance(servings, dict):
                # Already a structured object, ensure it has the right fields
                if "amount" not in servings and "unit" not in servings and "raw" not in servings:
                    # Might be old format, try to convert
                    if isinstance(servings.get("value"), (int, float, str)):
                        normalized["servings"] = {
                            "amount": str(servings.get("value")),
                            "unit": servings.get("unit"),
                            "raw": servings.get("raw") or str(servings.get("value", ""))
                        }
            elif isinstance(servings, (int, float)):
                # Convert number to Servings object
                normalized["servings"] = {
                    "amount": str(int(servings)),
                    "unit": None,
                    "raw": str(int(servings))
                }
            elif isinstance(servings, str):
                # String format - try to parse or use as raw
                normalized["servings"] = {
                    "amount": None,
                    "unit": None,
                    "raw": servings
                }
            elif servings is None:
                normalized["servings"] = None
            else:
                # Unknown format, set to None
                normalized["servings"] = None
        
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
                        # Handle both old format (quantity+unit) and new format (amount)
                        if "amount" in ing and ing["amount"]:
                            parts.append(str(ing["amount"]))
                        elif "quantity" in ing and ing["quantity"]:
                            parts.append(str(ing["quantity"]))
                        if "unit" in ing and ing["unit"] and "amount" not in ing:
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
                                    # Handle amount: use existing amount, or combine quantity+unit
                                    amount = ing.get("amount")
                                    if amount is None:
                                        qty = ing.get("quantity")
                                        unit = ing.get("unit")
                                        if qty or unit:
                                            parts = []
                                            if qty:
                                                parts.append(str(qty))
                                            if unit:
                                                parts.append(str(unit))
                                            amount = " ".join(parts) if parts else None
                                    
                                    normalized_ing = {
                                        "name": ing.get("name", ""),
                                        "amount": amount,
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
        
        # nutrition: normalize and filter to only allowed fields
        if "nutrition" in normalized and isinstance(normalized["nutrition"], dict):
            nutrition = normalized["nutrition"]
            # Map variant field names to correct schema fields and filter out extra fields
            normalized_nutrition = {}
            
            # calories
            calories = nutrition.get("calories")
            if isinstance(calories, str):
                try:
                    cleaned = ''.join(c for c in calories if c.isdigit() or c == '.')
                    normalized_nutrition["calories"] = float(cleaned) if cleaned else None
                except (ValueError, TypeError):
                    normalized_nutrition["calories"] = None
            elif isinstance(calories, (int, float)):
                normalized_nutrition["calories"] = float(calories) if calories >= 0 else None
            else:
                normalized_nutrition["calories"] = None
            
            # protein_g (map from protein or protein_g)
            protein = nutrition.get("protein_g") or nutrition.get("protein")
            if isinstance(protein, str):
                try:
                    cleaned = ''.join(c for c in protein if c.isdigit() or c == '.')
                    normalized_nutrition["protein_g"] = float(cleaned) if cleaned else None
                except (ValueError, TypeError):
                    normalized_nutrition["protein_g"] = None
            elif isinstance(protein, (int, float)):
                normalized_nutrition["protein_g"] = float(protein) if protein >= 0 else None
            else:
                normalized_nutrition["protein_g"] = None
            
            # fat_g (map from fat or fat_g)
            fat = nutrition.get("fat_g") or nutrition.get("fat")
            if isinstance(fat, str):
                try:
                    cleaned = ''.join(c for c in fat if c.isdigit() or c == '.')
                    normalized_nutrition["fat_g"] = float(cleaned) if cleaned else None
                except (ValueError, TypeError):
                    normalized_nutrition["fat_g"] = None
            elif isinstance(fat, (int, float)):
                normalized_nutrition["fat_g"] = float(fat) if fat >= 0 else None
            else:
                normalized_nutrition["fat_g"] = None
            
            # carbs_g (map from carbs, carbohydrates, or carbs_g)
            carbs = nutrition.get("carbs_g") or nutrition.get("carbs") or nutrition.get("carbohydrates")
            if isinstance(carbs, str):
                try:
                    cleaned = ''.join(c for c in carbs if c.isdigit() or c == '.')
                    normalized_nutrition["carbs_g"] = float(cleaned) if cleaned else None
                except (ValueError, TypeError):
                    normalized_nutrition["carbs_g"] = None
            elif isinstance(carbs, (int, float)):
                normalized_nutrition["carbs_g"] = float(carbs) if carbs >= 0 else None
            else:
                normalized_nutrition["carbs_g"] = None
            
            # per
            normalized_nutrition["per"] = nutrition.get("per") or "מנה"
            
            # Only keep allowed fields (remove extra fields like saturated_fat, sugar, fiber, sodium, etc.)
            normalized["nutrition"] = normalized_nutrition
        elif "nutrition" not in normalized:
            normalized["nutrition"] = None
        
        # Remove ingredients field (it's computed, not stored)
        normalized.pop("ingredients", None)
        
        # Remove extra fields not in Recipe model
        normalized.pop("description", None)
        normalized.pop("source_url", None)
        if "source_url" in normalized:
            normalized["source"] = normalized.pop("source_url")
        
        # Ensure required fields exist
        if "ingredientGroups" not in normalized:
            normalized["ingredientGroups"] = []
        if "instructionGroups" not in normalized:
            normalized["instructionGroups"] = []
        elif isinstance(normalized["instructionGroups"], list):
            # Normalize instructionGroups: handle both formats
            # Format 1: [{"name": "...", "instructions": [...]}]
            # Format 2: [{"instruction": "...", "step": 1}, ...] (wrong format from Gemini)
            normalized_instruction_groups = []
            for group in normalized["instructionGroups"]:
                if isinstance(group, dict):
                    # Check if it's the wrong format (has "instruction" and "step")
                    if "instruction" in group and "step" in group:
                        # Convert wrong format to correct format
                        instruction_text = group.get("instruction")
                        if instruction_text:
                            # Add to a single group with all instructions
                            if not normalized_instruction_groups:
                                normalized_instruction_groups.append({"name": "הוראות הכנה", "instructions": []})
                            normalized_instruction_groups[0]["instructions"].append(str(instruction_text))
                    elif "instructions" in group:
                        # Correct format - ensure it's a list
                        instructions = group.get("instructions", [])
                        if not isinstance(instructions, list):
                            instructions = [instructions] if instructions else []
                        # Remove extra fields like "step", "instruction"
                        clean_group = {
                            "name": group.get("name"),
                            "instructions": [str(inst) for inst in instructions if inst]
                        }
                        normalized_instruction_groups.append(clean_group)
                    elif "instruction" in group:
                        # Single instruction without step
                        instruction_text = group.get("instruction")
                        if instruction_text:
                            if not normalized_instruction_groups:
                                normalized_instruction_groups.append({"name": "הוראות הכנה", "instructions": []})
                            normalized_instruction_groups[0]["instructions"].append(str(instruction_text))
            
            # If we have normalized groups, use them; otherwise keep original structure
            if normalized_instruction_groups:
                normalized["instructionGroups"] = normalized_instruction_groups
            else:
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
                        # Remove extra fields
                        allowed_keys = {"name", "instructions"}
                        group_keys = list(group.keys())
                        for key in group_keys:
                            if key not in allowed_keys:
                                group.pop(key)
        if "notes" not in normalized:
            normalized["notes"] = []
        if "images" not in normalized:
            normalized["images"] = []
        
        return normalized

    # -------------------------
    # Prompts
    # -------------------------
    def _build_markdown_extraction_prompt(self, url: str, markdown_content: str, language: str = "he") -> str:
        """Build prompt for extracting recipe from markdown content. Simple parser prompt - no validation."""
        # Validate content is provided
        if not markdown_content or not markdown_content.strip():
            raise ValueError(f"Cannot build prompt: markdown_content is empty (type: {type(markdown_content)}, length: {len(markdown_content) if markdown_content else 0})")
        
        lang_label = "Hebrew" if language == "he" else "English"
        return f"""You are a strict JSON parser. Extract recipe data and return ONLY valid JSON matching the schema.

Language: {lang_label}

Rules:
- If a field is missing, set it to null or empty array.
- Do not explain.
- Do not validate.
- Do not add text outside JSON.
- Return only the JSON object.

CONTENT:
{markdown_content}
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
- servings: object with {{"amount": "string or null", "unit": "string or null", "raw": "string or null"}}. Example: {{"amount": "4", "unit": "מנות", "raw": "4 מנות"}}.
- ingredientGroups: [{{"name": null, "ingredients": [{{"amount": "quantity+unit combined (e.g., '1 כוס' or '250 מ״ל') or null", "name": "ingredient name (required)", "preparation": "preparation notes or null", "raw": "original text or null"}}]}}]
- ingredients: Flat list of strings ["ingredient 1", "ingredient 2"]
- nutrition: Numbers only (not "not specified"). If unknown: null or 0.

Do not invent, do not change, nutrition information is mandatory if available.
"""

