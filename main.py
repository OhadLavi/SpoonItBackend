# -*- coding: utf-8 -*-
"""
SpoonIt API — site-agnostic, LLM-first, Cloud Run friendly

Key changes vs your last file:
- /extract_recipe NEVER returns HTTP 403; returns 200 with a JSON error payload
  so the app can client-fetch and resend html_content when sites block server IPs.
- Playwright is lazy-imported; uses wait_until="networkidle" + scroll + main/article/body innerText.
- Gemini uses Structured Outputs (JSON) with a response schema (Google GenAI SDK).
"""

from __future__ import annotations

import asyncio
import base64
import io
import json
import logging
import os
import random
import re
from typing import Optional, Dict, Any, List, Tuple

import httpx
import uvicorn
import google.generativeai as genai
from bs4 import BeautifulSoup  # used in /proxy_image fallback
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from PIL import Image, ImageOps, ImageFilter
from pydantic import BaseModel, Field

# =============================================================================
# Logging
# =============================================================================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
    handlers=[logging.FileHandler("recipe_keeper.log", encoding="utf-8"), logging.StreamHandler()],
)
logger = logging.getLogger("recipe-keeper")

# =============================================================================
# Config
# =============================================================================
OLLAMA_API_URL = "http://127.0.0.1:11434/api/generate"
MODEL_NAME = "gemma3:4b"

HTTP_TIMEOUT = 30.0
PLAYWRIGHT_TIMEOUT_MS = 45000
FETCH_MAX_BYTES = 2_500_000

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")  # any Gemini model supporting structured outputs

# Configure Gemini API
if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)

# =============================================================================
# Headers / UA rotation
# =============================================================================
BROWSER_UAS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15",
    "Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Mobile Safari/537.36",
]

def _default_headers() -> dict:
    ua = random.choice(BROWSER_UAS)
    return {
        "User-Agent": ua,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "he-IL,he;q=0.9,en-US;q=0.8,en;q=0.7",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
        "Referer": "https://www.google.com/",
        "DNT": "1",
        "Sec-Fetch-Dest": "document",
        "Sec-Fetch-Mode": "navigate",
        "Sec-Fetch-Site": "cross-site",
        "Upgrade-Insecure-Requests": "1",
    }

# Basic detector for bot/403 blocker pages
_BLOCK_PATTERNS = re.compile(
    r"(access\s*denied|forbidden|block(ed)?|request was denied|captcha|just a moment|cloudflare|"
    r"permission\s*denied|not\s*authorized|are you a human|malicious traffic)",
    re.IGNORECASE,
)

def _looks_blocked(text: str) -> bool:
    if not text:
        return True
    if len(text) < 500:  # tiny pages are often interstitials / blocks
        return True
    return bool(_BLOCK_PATTERNS.search(text))

# =============================================================================
# Errors
# =============================================================================
class APIError(Exception):
    def __init__(self, message: str, status_code: int = 500, details: Optional[Dict[str, Any]] = None):
        super().__init__(message)
        self.message = message
        self.status_code = status_code
        self.details = details or {}

# =============================================================================
# Schemas
# =============================================================================
class ChatRequest(BaseModel):
    message: str
    language: str = "en"

class RecipeExtractionRequest(BaseModel):
    url: str
    html_content: Optional[str] = None  # when server is blocked, client sends page HTML here

class ImageExtractionRequest(BaseModel):
    image_data: str  # base64 (with or without data URI prefix)

class CustomRecipeRequest(BaseModel):
    groceries: str
    description: str

class IngredientGroup(BaseModel):
    category: str = ""
    ingredients: List[str] = Field(default_factory=list, min_length=0)

class RecipeModel(BaseModel):
    title: str = ""
    description: str = ""
    ingredients: List[str] = Field(default_factory=list, min_length=0)
    ingredientsGroups: Optional[List[IngredientGroup]] = None
    instructions: List[str] = Field(default_factory=list, min_length=0)
    prepTime: int = 0
    cookTime: int = 0
    servings: int = 1
    tags: List[str] = Field(default_factory=list, min_length=0)
    notes: str = ""
    source: str = ""
    imageUrl: str = ""

# =============================================================================
# Utils & Normalization
# =============================================================================
def safe_strip(v: Any) -> str:
    return "" if v is None else str(v).strip()

def ensure_list(value: Any) -> list:
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return list(value.values())
    return [value] if value else []

def remove_exact_duplicates(seq: List[str]) -> List[str]:
    seen = set()
    out: List[str] = []
    for item in seq:
        if item and item not in seen:
            seen.add(item)
            out.append(item)
    return out

def parse_time_value(time_str: Any) -> int:
    if isinstance(time_str, int):
        return time_str
    if isinstance(time_str, str):
        try:
            return int(time_str)
        except ValueError:
            return 0
    return 0

def parse_servings(servings_str: Any) -> int:
    if isinstance(servings_str, int):
        return servings_str
    if isinstance(servings_str, str):
        try:
            return int(servings_str)
        except ValueError:
            return 1
    return 1

# =============================================================================
# LLM JSON repair helpers
# =============================================================================
def _strip_code_fences(text: str) -> str:
    s = text.strip()
    m = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", s, re.IGNORECASE)
    if m:
        return m.group(1).strip()
    if s.startswith("```"):
        s = s.split("```", 1)[1]
    if s.endswith("```"):
        s = s.rsplit("```", 1)[0]
    if s.lstrip().lower().startswith("json\n"):
        s = s.lstrip()[5:]
    return s.strip()

def _normalize_quotes(text: str) -> str:
    return (
        text.replace("\u201c", '"').replace("\u201d", '"')
        .replace("\u2018", "'").replace("\u2019", "'")
    )

def _remove_trailing_commas(s: str) -> str:
    return re.sub(r",(\s*[}\]])", r"\1", s)

def _quote_unquoted_keys(s: str) -> str:
    return re.sub(r'(?<=[{,])\s*([A-Za-z_][A-Za-z0-9_\-]*)\s*:', r'"\1":', s)

def _quote_unquoted_string_values(s: str) -> str:
    s = re.sub(
        r'(:\s*)(?!-?\d+(?:\.\d+)?\b)(?!true\b|false\b|null\b)(?!\"|\{|\[)([^,\}\]]+)',
        lambda m: m.group(1) + '"' + m.group(2).strip().replace('"', '\\"') + '"',
        s, flags=re.IGNORECASE,
    )
    s = re.sub(
        r'(?:(?<=\[)|(?<=,))\s*(?!-?\d+(?:\.\d+)?\b)(?!true\b|false\b|null\b)(?!\"|\{|\[)([^,\]\}]+)\s*(?=,|\])',
        lambda m: ' "' + m.group(1).strip().replace('"', '\\"') + '"',
        s, flags=re.IGNORECASE,
    )
    return s

def _collapse_whitespace(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()

async def extract_and_parse_llm_json(output: str) -> dict:
    s = _strip_code_fences(_normalize_quotes(output))
    s = _remove_trailing_commas(_quote_unquoted_keys(s))
    try:
        return json.loads(s)
    except json.JSONDecodeError:
        pass
    s2 = _quote_unquoted_string_values(s)
    s2 = _remove_trailing_commas(s2)
    try:
        return json.loads(s2)
    except json.JSONDecodeError:
        s3 = _collapse_whitespace(s2)
        s3 = _remove_trailing_commas(s3)
        return json.loads(s3)

# =============================================================================
# Normalization to RecipeModel
# =============================================================================
def normalize_recipe_fields(recipe_data: dict) -> RecipeModel:
    if not recipe_data.get("title") and recipe_data.get("recipeName"):
        recipe_data["title"] = recipe_data["recipeName"]

    prep_time = parse_time_value(recipe_data.get("prepTime", 0))
    cook_time = parse_time_value(recipe_data.get("cookTime", 0))

    if "servings" in recipe_data:
        servings = parse_servings(recipe_data["servings"])
    elif "recipeYield" in recipe_data:
        servings = parse_servings(recipe_data["recipeYield"])
    else:
        servings = 1

    ingredients = ensure_list(recipe_data.get("ingredients", []))
    ingredients = [str(x).strip() for x in ingredients if x]
    ingredients = remove_exact_duplicates(ingredients)

    instructions = recipe_data.get("instructions", [])
    if isinstance(instructions, str):
        instructions = [x.strip() for x in instructions.split("\n") if x.strip()]
    else:
        instructions = [str(x).strip() for x in ensure_list(instructions) if x]
    instructions = remove_exact_duplicates(instructions)

    tags = recipe_data.get("tags", [])
    if isinstance(tags, str):
        tags = [x.strip() for x in tags.split(",") if x.strip()]
    else:
        tags = [str(x).strip() for x in ensure_list(tags) if x]

    return RecipeModel(
        title=safe_strip(recipe_data.get("title", "")),
        description=safe_strip(recipe_data.get("description", "")),
        ingredients=ingredients,
        instructions=instructions,
        prepTime=prep_time,
        cookTime=cook_time,
        servings=servings,
        tags=tags,
        notes=safe_strip(recipe_data.get("notes", "")),
        source=safe_strip(recipe_data.get("source", "")),
        imageUrl=safe_strip(recipe_data.get("imageUrl", "")),
    )

# =============================================================================
# OCR
# =============================================================================
def extract_text_from_image(image_bytes: bytes) -> str:
    try:
        image = Image.open(io.BytesIO(image_bytes))
        img = ImageOps.exif_transpose(image).convert("L")
        img = img.filter(ImageFilter.SHARPEN)
        img = img.point(lambda x: 0 if x < 160 else 255, mode="1")
        config = "--psm 6"
        import pytesseract  # lazy import is fine
        text = pytesseract.image_to_string(img, lang="eng+heb", config=config)
        logger.debug("[OCR] extracted %d chars", len(text))
        return text
    except Exception as e:
        logger.error("[OCR] failure: %s", e, exc_info=True)
        raise APIError(f"OCR processing failed: {str(e)}")

# =============================================================================
# HTTP Fetchers (orchestrated)
# =============================================================================
async def _httpx_fetch(url: str) -> str:
    async with httpx.AsyncClient(
        timeout=HTTP_TIMEOUT,
        headers=_default_headers(),
        follow_redirects=True,
    ) as client:
        r = await client.get(url)
        r.raise_for_status()
        html = r.text
        html = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL | re.IGNORECASE)
        html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.DOTALL | re.IGNORECASE)
        text = re.sub(r'<[^>]+>', ' ', html)
        text = re.sub(r'\s+', ' ', text)
        if len(text.encode('utf-8')) > 50_000:
            text = text[:50_000]
        return text.strip()

async def _playwright_fetch(url: str) -> str:
    if os.getenv("DISABLE_PLAYWRIGHT_FETCH", "").lower() in ("1", "true", "yes"):
        raise RuntimeError("Playwright fetch disabled by env")

    # Allow overriding the per-try timeout via env; default ~45s per your logs
    per_try_timeout_ms = int(os.getenv("PLAYWRIGHT_TIMEOUT_MS", str(PLAYWRIGHT_TIMEOUT_MS)))
    max_retries = 2  # total 3 tries: 0,1,2

    async with async_playwright() as p:
        browser = await p.chromium.launch(
            headless=True,
            args=[
                "--no-sandbox",
                "--disable-dev-shm-usage",
                "--disable-gpu",
                "--disable-blink-features=AutomationControlled",
            ],
        )
        try:
            for attempt in range(max_retries + 1):
                context = await browser.new_context(
                    user_agent=random.choice(BROWSER_UAS),
                    locale="he-IL",
                    extra_http_headers=_default_headers(),
                    bypass_csp=True,
                    viewport={"width": 1366, "height": 900},
                )

                # Block heavy/irrelevant resources so we don’t wait forever on fonts/ads/media.
                # This speeds up and avoids never-Idle pages. Docs: page.route / Route.abort
                # https://playwright.dev/python/docs/api/class-route
                await context.route(
                    "**/*",
                    lambda route: asyncio.create_task(
                        route.abort()
                        if route.request.resource_type in {"image", "media", "font", "stylesheet"}
                        else route.continue_()
                    ),
                )

                page = await context.new_page()

                # Light stealth
                await page.add_init_script("""
                    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
                    window.chrome = { runtime: {} };
                    Object.defineProperty(navigator, 'plugins', { get: () => [1,2,3] });
                    Object.defineProperty(navigator, 'languages', { get: () => ['he-IL','he','en-US','en'] });
                """)

                # Some sites never reach "networkidle". Prefer domcontentloaded → load → (last resort) networkidle.
                wait_chain = ["domcontentloaded", "load", "networkidle"]

                try:
                    last_error = None
                    for wu in wait_chain:
                        try:
                            await page.goto(url, wait_until=wu, timeout=per_try_timeout_ms)
                            break
                        except Exception as e:
                            last_error = e
                    else:
                        raise last_error or TimeoutError("page.goto failed for all wait states")

                    # Try element-based readiness; often more reliable than load states.
                    # Docs suggest waiting for specific selectors instead of global load (h1, main/article, body).
                    # https://autify.com/blog/playwright-wait-for-page-to-load  (concept) 
                    sel = "main, article, [role='main'], .entry-content, .post-content, .recipe, body"
                    try:
                        await page.wait_for_selector(sel, timeout=3000)
                    except Exception:
                        pass

                    # Scroll a bit to trigger lazy content
                    for _ in range(3):
                        await page.mouse.wheel(0, 1200)
                        await page.wait_for_timeout(300)

                    # Prefer meaningful containers
                    content_text = ""
                    for candidate in ["main", "article", "[role='main']", ".entry-content", ".post-content", ".recipe", "body"]:
                        try:
                            el = await page.query_selector(candidate)
                            if el:
                                t = await el.inner_text()
                                if t and len(t) > len(content_text):
                                    content_text = t
                        except Exception:
                            continue

                    # Fallback to full HTML text-stripping if still small
                    if len(content_text or "") < 600:
                        raw_html = await page.content()
                        raw_html = re.sub(r'<script[^>]*>.*?</script>', '', raw_html, flags=re.DOTALL | re.IGNORECASE)
                        raw_html = re.sub(r'<style[^>]*>.*?</style>', '', raw_html, flags=re.DOTALL | re.IGNORECASE)
                        content_text = re.sub(r'<[^>]+>', ' ', raw_html)

                    text = re.sub(r"\s+", " ", (content_text or "")).strip()
                    if len(text.encode("utf-8")) > 50_000:
                        text = text[:50_000]

                    # If the body looks like a block page, try an APIRequestContext fetch that shares cookies.
                    # https://playwright.dev/python/docs/api/class-apirequestcontext
                    if _looks_blocked(text):
                        try:
                            resp = await context.request.get(url, headers=_default_headers(), timeout=per_try_timeout_ms/1000)
                            if resp.ok:
                                html = await resp.text()
                                html = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL | re.IGNORECASE)
                                html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.DOTALL | re.IGNORECASE)
                                tx = re.sub(r'<[^>]+>', ' ', html)
                                tx = re.sub(r'\s+', ' ', tx)
                                text = tx.strip()
                        except Exception:
                            pass

                    await context.close()
                    return text
                except Exception as e:
                    try:
                        await context.close()
                    except Exception:
                        pass
                    if attempt < max_retries:
                        await asyncio.sleep(0.8 * (attempt + 1))
                        continue
                    raise e
        finally:
            await browser.close()

async def fetch_html_content(url: str) -> str:
    try:
        text = await _httpx_fetch(url)
        if _looks_blocked(text):
            logger.warning("[FETCH] httpx content looks blocked/short (%d chars). Trying Playwright.", len(text))
            text = await _playwright_fetch(url)
        if _looks_blocked(text):
            raise APIError(
                "Remote site is blocking server fetch (403). Ask client to supply html_content.",
                status_code=403,
                details={"code": "FETCH_FORBIDDEN", "url": url},
            )
        return text
    except httpx.HTTPStatusError as e:
        status = e.response.status_code
        logger.warning("[FETCH] httpx status=%s for %s", status, url)
        if status in (401, 403, 406, 429, 451, 503):
            try:
                text = await _playwright_fetch(url)
                if _looks_blocked(text):
                    raise APIError(
                        "Remote site is blocking server fetch (403). Ask client to supply html_content.",
                        status_code=403,
                        details={"code": "FETCH_FORBIDDEN", "url": url},
                    )
                return text
            except APIError:
                raise
            except Exception as e2:
                logger.warning("[FETCH] Playwright fallback failed: %s", e2, exc_info=True)
                raise APIError(
                    "Remote site is blocking server fetch (403). Ask client to supply html_content.",
                    status_code=403,
                    details={"code": "FETCH_FORBIDDEN", "url": url},
                )
        raise APIError(
            f"Fetch failed with status {status}.",
            status_code=status,
            details={"code": "FETCH_FAILED", "url": url},
        )


# =============================================================================
# FastAPI app
# =============================================================================
app = FastAPI(
    title="SpoonIt API",
    version="1.4.0",
    description="Generic recipe extraction via LLM Structured Outputs + Playwright fallback (Heb/Eng).",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Disposition", "Access-Control-Allow-Origin"],
)

@app.exception_handler(APIError)
async def api_error_handler(request, exc: APIError):
    logger.error("APIError: %s | details=%s", exc.message, exc.details)
    return JSONResponse(status_code=exc.status_code, content={"error": exc.message, "details": exc.details})

@app.get("/")
async def root():
    return {"message": "Welcome to SpoonIt API", "docs": "/docs", "redoc": "/redoc"}

@app.get("/health")
async def health():
    return {"status": "ok"}

# ---------------------------------------------------------------------------
# Chat (Ollama) — unchanged
# ---------------------------------------------------------------------------
@app.post("/chat")
async def chat(request: ChatRequest):
    sys_prompt = (
        "You are a helpful assistant. Please respond in Hebrew, clearly and well-formatted."
        if request.language.lower().startswith("he")
        else "You are a helpful assistant. Please respond in English, clearly and well-formatted."
    )
    prompt = f"{sys_prompt}\n\nUser: {request.message}\nAssistant:"
    payload = {"model": MODEL_NAME, "prompt": prompt, "stream": False}
    try:
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
            r = await client.post(OLLAMA_API_URL, json=payload)
            r.raise_for_status()
            data = r.json()
        return {"response": data.get("response", ""), "model": MODEL_NAME}
    except Exception as e:
        logger.error("[CHAT] error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail="Ollama request failed")

# ---------------------------------------------------------------------------
# Gemini Structured Outputs — helpers
# ---------------------------------------------------------------------------
def _gemini_model():
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY not configured")
    # Use Structured Outputs (JSON) with schema
    # Docs: set response_mime_type + response_json_schema/response_schema. :contentReference[oaicite:4]{index=4}
    return genai.GenerativeModel(GEMINI_MODEL)

def _gemini_generation_config():
    # Google GenAI SDK supports response_mime_type/response_schema via GenerationConfig. :contentReference[oaicite:5]{index=5}
    return genai.GenerationConfig(
        response_mime_type="application/json",
        response_schema={
            "type": "object",
            "properties": {
                "title": {"type": "string", "minLength": 3},
                "description": {"type": "string"},
                "ingredients": {"type": "array", "minItems": 4, "items": {"type": "string", "minLength": 2}},
                "ingredientsGroups": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "category": {"type": "string"},
                            "ingredients": {"type": "array", "items": {"type": "string"}}
                        },
                        "required": ["category", "ingredients"]
                    }
                },
                "instructions": {"type": "array", "minItems": 4, "items": {"type": "string", "minLength": 4}},
                "prepTime": {"type": "integer"},
                "cookTime": {"type": "integer"},
                "servings": {"type": "integer"},
                "tags": {"type": "array", "items": {"type": "string"}},
                "notes": {"type": "string"},
                "source": {"type": "string"},
                "imageUrl": {"type": "string"},
            },
            "required": ["title", "ingredients", "instructions"]
        },
        temperature=0,
        max_output_tokens=1800,
    )

def _gemini_prompt(url: str, page_text: str) -> str:
    return f"""
Extract the recipe information from the following webpage content.

URL: {url}

Rules:
- COPY facts from the page; do NOT invent or paraphrase.
- Keep headers for ingredients groups EXACT as written (e.g., "למילוי:", "לבצק:", etc.).
- Steps should be sequential and concise; preserve the page’s wording as much as possible.
- If no recipe exists, return JSON with only: {{"title":"", "ingredients":[], "instructions":[]}}.

PAGE TEXT:
{page_text}
"""

# ---------------------------------------------------------------------------
# Core extraction
# ---------------------------------------------------------------------------
@app.post("/extract_recipe")
async def extract_recipe(req: RecipeExtractionRequest):
    url = req.url.strip()
    logger.info("[FLOW] extract_recipe START | url=%s", url)
    if not url.startswith("http"):
        # 200 with error payload (never 4xx) to avoid breaking mobile client flows
        return {"error": "INVALID_URL", "message": "URL must start with http(s)://"}

    page_text: Optional[str] = None
    if req.html_content:
        logger.info("[FLOW] using HTML content provided by client, length=%d", len(req.html_content))
        html = req.html_content
        html = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL | re.IGNORECASE)
        html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.DOTALL | re.IGNORECASE)
        page_text = re.sub(r'<[^>]+>', ' ', html)
        page_text = re.sub(r'\s+', ' ', page_text).strip()
        if len(page_text.encode('utf-8')) > 50_000:
            page_text = page_text[:50_000]
    else:
        # Server-side fetch first; if blocked, return JSON error (HTTP 200) so the client
        # can fetch the page and re-post html_content.
        fetched, fetch_err = await fetch_html_content(url)
        if fetch_err:
            return fetch_err  # 200 with error JSON (html_required=true)
        page_text = fetched or ""

    if not page_text or len(page_text) < 80:
        return {"error": "TOO_LITTLE_TEXT", "message": "Page has too little visible text to extract."}

    # Gemini Structured Outputs
    try:
        model = _gemini_model()
        cfg = _gemini_generation_config()
        prompt = _gemini_prompt(url, page_text)

        # NOTE: With Structured Outputs, the model returns strictly JSON. :contentReference[oaicite:6]{index=6}
        result = model.generate_content(prompt, generation_config=cfg)
        text = (result.text or "").strip()

        if not text:
            logger.error("[LLM] empty response. First 160 page_text chars: %r", page_text[:160])
            return {"error": "LLM_EMPTY", "message": "Model returned empty response"}

        # Parse JSON; repair if necessary (should be rare with structured outputs)
        try:
            recipe_dict = json.loads(text)
        except Exception:
            recipe_dict = await extract_and_parse_llm_json(text)

        # Force source
        if not recipe_dict.get("source"):
            recipe_dict["source"] = url

        # Number instructions (keep content, just add numbers if missing)
        instructions = recipe_dict.get("instructions", [])
        numbered = []
        for i, instruction in enumerate(instructions, 1):
            s = str(instruction).strip()
            s = re.sub(r'^\d+[\.\)]\s*', '', s)
            numbered.append(f"{i}. {s}")
        recipe_dict["instructions"] = numbered

        # Optional groups normalization
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

        # Final model
        recipe_model = RecipeModel(
            title=recipe_dict.get("title", ""),
            description=recipe_dict.get("description", ""),
            ingredients=recipe_dict.get("ingredients", []),
            ingredientsGroups=ingredients_groups,
            instructions=recipe_dict["instructions"],
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
            recipe_model.title, len(recipe_model.ingredients), len(recipe_model.instructions),
            recipe_model.prepTime, recipe_model.cookTime
        )
        return recipe_model.model_dump()

    except Exception as e:
        logger.error("[FLOW] unexpected LLM error: %s", e, exc_info=True)
        return {"error": "UNEXPECTED", "message": f"Error calling Gemini API: {str(e)}"}

# ---------------------------------------------------------------------------
# Extract recipe from Base64 image
# ---------------------------------------------------------------------------
@app.post("/extract_recipe_from_image")
async def extract_recipe_from_image(req: ImageExtractionRequest):
    try:
        data = req.image_data
        if "," in data:
            data = data.split(",", 1)[1]
        image_bytes = base64.b64decode(data)
        text = extract_text_from_image(image_bytes)
        if not text or len(text) < 40:
            return {"error": "IMG_TEXT_TOO_SHORT", "message": "Not enough text extracted from image"}

        prompt = (
            "את/ה מומחה/ית לחילוץ מתכונים. החזר/י אך ורק JSON תקין עם המפתחות: "
            "title, description, ingredients, instructions, prepTime, cookTime, servings, tags, imageUrl, source.\n"
            "מספרים כמספרים (int), ללא המצאות."
            f"\n\nטקסט מהתמונה:\n{text}"
        )
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

    except Exception as e:
        logger.error("[IMG] error: %s", e, exc_info=True)
        return {"error": "IMG_UNEXPECTED", "message": f"Error processing image: {str(e)}"}

# ---------------------------------------------------------------------------
# Upload recipe image (multipart)
# ---------------------------------------------------------------------------
@app.post("/upload_recipe_image")
async def upload_recipe_image(file: UploadFile = File(...)):
    try:
        contents = await file.read()
        text = extract_text_from_image(contents)
        if not text or len(text) < 40:
            return {"error": "IMG_TEXT_TOO_SHORT", "message": "Not enough text extracted from image"}

        prompt = (
            "את/ה מומחה/ית לחילוץ מתכונים. החזר/י אך ורק JSON תקין עם המפתחות: "
            "title, description, ingredients, instructions, prepTime, cookTime, servings, tags, imageUrl, source.\n"
            "מספרים כמספרים (int), ללא המצאות."
            f"\n\nטקסט מהתמונה:\n{text}"
        )
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

    except Exception as e:
        logger.error("[UPLOAD] error: %s", e, exc_info=True)
        return {"error": "UPLOAD_UNEXPECTED", "message": f"Error processing uploaded image: {str(e)}"}

# ---------------------------------------------------------------------------
# Custom recipe generation
# ---------------------------------------------------------------------------
@app.post("/custom_recipe")
async def custom_recipe(req: CustomRecipeRequest):
    try:
        prompt = (
            "את/ה יוצר/ת מתכונים. בנה/י JSON יחיד ותקין בלבד.\n"
            f"מצרכים זמינים: {req.groceries}\n"
            f"תיאור בקשה: {req.description}\n\n"
            "החזר/י אך ורק אובייקט עם המפתחות: "
            "{title, description, ingredients, instructions, prepTime, cookTime, servings, tags, imageUrl, source}.\n"
            "חוקים: JSON תקין בלבד; ללא פסיקים מיותרים; מספרים לא במרכאות."
        )
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

    except Exception as e:
        logger.error("[CUSTOM] error: %s", e, exc_info=True)
        return {"error": "CUSTOM_UNEXPECTED", "message": "An unexpected error occurred during custom recipe generation"}

# ---------------------------------------------------------------------------
# Simple image proxy (CORS bypass)
# ---------------------------------------------------------------------------
@app.get("/proxy_image")
async def proxy_image(url: str):
    try:
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT, follow_redirects=True) as client:
            r = await client.get(url)
            r.raise_for_status()
            content_type = r.headers.get("Content-Type", "image/jpeg")
            content = r.content

            if not content_type or not content_type.startswith("image/"):
                logger.warning("[PROXY] Non-image content type: %s for URL: %s", content_type, url)
                if content_type and "text/html" in content_type:
                    soup = BeautifulSoup(content, "html.parser")
                    img_tags = soup.find_all("img")
                    if img_tags:
                        for img in img_tags:
                            src = img.get("src")
                            if src and (src.startswith("http") or src.startswith("//")):
                                if src.startswith("//"):
                                    src = "https:" + src
                                logger.info("[PROXY] Found image in HTML: %s", src)
                                return await proxy_image(src)

                raise HTTPException(status_code=400, detail="URL does not point to an image")

        return Response(
            content=content,
            media_type=content_type,
            headers={"Access-Control-Allow-Origin": "*", "Cache-Control": "public, max-age=86400"},
        )
    except Exception as e:
        logger.error("[PROXY] error: %s", e, exc_info=True)
        return {"error": "PROXY_UNEXPECTED", "message": f"Failed to proxy image: {str(e)}"}

# =============================================================================
# Entrypoint (Cloud Run requires binding to 0.0.0.0:$PORT)
# =============================================================================
if __name__ == "__main__":
    # Cloud Run runtime contract: listen on $PORT (default 8080). :contentReference[oaicite:7]{index=7}
    uvicorn.run("main:app", host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
