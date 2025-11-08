# -*- coding: utf-8 -*-
"""
SpoonIt Backend — main.py (LLM-first, site-agnostic, Cloud Run ready)

Pipeline:
  1) Fetch (httpx; optional Playwright fallback for 403/JS sites)
  2) Reduce HTML → visible text (prefer main/article, innerText)
  3) Ask Gemini for STRICT JSON (responseMimeType + JSON Schema)
  4) Validate (min items, no placeholder title); return recipe or error

Env:
  GEMINI_API_KEY=...
  GEMINI_MODEL=gemini-2.5-flash
  PLAYWRIGHT_ENABLED=0/1         (default 0; enable if many sites block httpx)
  CONTEXT_CHARS=15000            (trimmed page text for the LLM)
  PORT=8080                      (Cloud Run injects; we bind to 0.0.0.0:PORT)
"""

from __future__ import annotations
import os
import re
import json
import logging
from typing import Any, Dict, List, Optional, Tuple

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from bs4 import BeautifulSoup

# -------------------- Logging --------------------
LOGGER_NAME = "recipe-keeper"
logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s")
logger = logging.getLogger(LOGGER_NAME)

# -------------------- Config --------------------
HTTP_TIMEOUT = httpx.Timeout(25.0, connect=10.0)
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
PLAYWRIGHT_ENABLED = os.getenv("PLAYWRIGHT_ENABLED", "0") == "1"
CONTEXT_CHARS = int(os.getenv("CONTEXT_CHARS", "15000"))

# -------------------- API Models --------------------
class RecipeModel(BaseModel):
    title: str
    description: str = ""
    ingredients: List[str]
    instructions: List[str]
    prepTime: int = 0
    cookTime: int = 0
    servings: int = 0
    tags: List[str] = []
    imageUrl: str = ""
    source: str = ""

class ExtractRequest(BaseModel):
    url: str

class ExtractResponse(BaseModel):
    ok: bool
    recipe: Optional[RecipeModel] = None
    error: Optional[str] = None
    diagnostics: Optional[Dict[str, Any]] = None

app = FastAPI()

# -------------------- Utils --------------------
def clean_text(s: str | None) -> str:
    if not s:
        return ""
    s = re.sub(r"\s+", " ", s)
    return s.strip()

def _domain(url: str) -> str:
    try:
        return re.sub(r"^https?://", "", url).split("/")[0].replace("www.", "")
    except Exception:
        return ""

# -------------------- Fetchers --------------------
async def fetch_html_httpx(url: str) -> str:
    headers = {"User-Agent": "Mozilla/5.0 (compatible; SpoonIt/1.0)"}
    async with httpx.AsyncClient(timeout=HTTP_TIMEOUT, headers=headers) as client:
        r = await client.get(url)
        r.raise_for_status()
        return r.text

async def fetch_html_playwright(url: str) -> Tuple[str, str]:
    """
    Returns (html, main_text). Requires PLAYWRIGHT_ENABLED=1 and that
    browsers are installed in the image:
      pip install playwright && playwright install --with-deps chromium
    """
    try:
        from playwright.async_api import async_playwright
    except Exception as e:
        raise RuntimeError(f"Playwright not available: {e}")

    async with async_playwright() as p:
        browser = await p.chromium.launch(args=["--no-sandbox", "--disable-dev-shm-usage"])
        page = await browser.new_page(user_agent="Mozilla/5.0 (compatible; SpoonIt/1.0)")
        await page.goto(url, wait_until="networkidle", timeout=45000)

        # small scrolls help lazy content
        for _ in range(3):
            await page.mouse.wheel(0, 1200)
            await page.wait_for_timeout(400)

        # Prefer visible, user-facing text for LLM
        main_text = await page.evaluate("""
            () => {
              const root = document.querySelector('main, article') || document.body;
              const txt = root && (root.innerText || root.textContent) || '';
              return txt;
            }
        """)
        html = await page.content()
        await browser.close()
        return html, (main_text or "")

async def fetch_html(url: str) -> Tuple[str, Dict[str, Any], str]:
    """
    Returns (html, diagnostics, text_primary_for_llm)
    """
    diag: Dict[str, Any] = {"domain": _domain(url)}
    # Try httpx first (fast, cheap)
    try:
        html = await fetch_html_httpx(url)
        diag["fetch"] = "httpx"
        text_primary = ""
        return html, diag, text_primary
    except Exception as e:
        logger.info("[FETCH] httpx failed: %s", e)
        diag["httpx_error"] = str(e)

    # Optional Playwright fallback for JS/blocked pages
    if PLAYWRIGHT_ENABLED:
        try:
            html, main_text = await fetch_html_playwright(url)
            diag["fetch"] = "playwright"
            return html, diag, main_text
        except Exception as e2:
            diag["playwright_error"] = str(e2)
            raise

    raise

# -------------------- HTML → Visible Text --------------------
def html_to_visible_text(html: str) -> str:
    soup = BeautifulSoup(html, "html.parser")
    # remove unlikely noise
    for tag in soup(["script", "style", "noscript"]):
        tag.decompose()
    for attr in ("header", "footer", "nav", "aside"):
        for el in soup.find_all(attr):
            el.decompose()
    # prefer main/article if present
    container = soup.select_one("main") or soup.select_one("article") or soup
    text = container.get_text(" ", strip=True)
    return text[:CONTEXT_CHARS]

# -------------------- LLM (Gemini) --------------------
async def gemini_structured_extract(url: str, page_text: str) -> Dict[str, Any]:
    """
    Use Gemini Structured Outputs to force valid JSON with minimum fields.
    """
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY not configured")

    system_instruction = (
        "You are a precise recipe extractor for Hebrew and English websites. "
        "Extract ONLY what is present in the provided page text. Do not invent. "
        "If the page is not a recipe, return: {\"error\":\"no_recipe\"}. "
        "Avoid using the site/brand name as the title."
    )

    user_prompt = (
        "Task: Extract a cooking recipe from the following page.\n"
        f"URL: {url}\n"
        "Rules:\n"
        "- Return only fields that truly appear on the page.\n"
        "- Steps should be concise, sequential instructions.\n"
        "- If not a recipe, return {\"error\":\"no_recipe\"}.\n"
        "PageText:\n" + page_text
    )

    generation_config: Dict[str, Any] = {
        "responseMimeType": "application/json",
        "responseJsonSchema": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "minLength": 3},
                "description": {"type": "string"},
                "ingredients": {
                    "type": "array",
                    "minItems": 4,
                    "items": {"type": "string", "minLength": 2},
                },
                "instructions": {
                    "type": "array",
                    "minItems": 4,
                    "items": {"type": "string", "minLength": 4},
                },
                "prepTime": {"type": "integer"},
                "cookTime": {"type": "integer"},
                "servings": {"type": "integer"},
                "tags": {"type": "array", "items": {"type": "string"}},
                "imageUrl": {"type": "string"},
                "source": {"type": "string"},
                "error": {"type": "string"},
            },
            "required": ["title", "ingredients", "instructions"],
        },
        "temperature": 0,
        "maxOutputTokens": 1800,
    }

    payload = {
        "contents": [
            {"role": "user", "parts": [{"text": f"{system_instruction}\n\n{user_prompt}"}]}
        ],
        "generationConfig": generation_config,
    }

    url_api = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent"
    headers = {"x-goog-api-key": GEMINI_API_KEY, "Content-Type": "application/json"}

    async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
        r = await client.post(url_api, headers=headers, json=payload)
        r.raise_for_status()
        data = r.json()

    text_out = _extract_text_from_candidates(data)

    # Retry path (relaxed schema) if empty/odd shape (e.g., MAX_TOKENS)
    if not text_out:
        logger.warning("[GEMINI] empty text; retrying with relaxed schema")
        relaxed_cfg = dict(generation_config)
        relaxed_cfg.pop("responseJsonSchema", None)
        relaxed_payload = {
            "contents": [
                {"role": "user", "parts": [{"text": f"{system_instruction}\n\n{user_prompt}\nReturn ONLY JSON."}]}
            ],
            "generationConfig": relaxed_cfg,
        }
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
            r2 = await client.post(url_api, headers=headers, json=relaxed_payload)
            r2.raise_for_status()
            data2 = r2.json()
        text_out = _extract_text_from_candidates(data2)

    if not text_out:
        raise HTTPException(status_code=500, detail="Gemini returned no text")

    text_out = text_out.strip()
    text_out = re.sub(r"^```(?:json)?|```$", "", text_out).strip()

    # Parse JSON (fallback: first JSON object substring)
    try:
        return json.loads(text_out)
    except Exception:
        m = re.search(r"\{[\s\S]*\}", text_out)
        if m:
            return json.loads(m.group(0))
        raise HTTPException(status_code=500, detail="Gemini JSON parse error")

def _extract_text_from_candidates(data: Dict[str, Any]) -> str:
    cands = data.get("candidates") or []
    if not cands:
        return ""
    cand = cands[0]
    content = cand.get("content")
    parts = []
    if isinstance(content, dict):
        parts = content.get("parts", [])
    elif isinstance(content, list):
        for it in content:
            if isinstance(it, dict):
                parts.extend(it.get("parts", []))
    out = ""
    for p in parts:
        if isinstance(p, dict) and isinstance(p.get("text"), str):
            out += p["text"]
    return out

# -------------------- Orchestrator --------------------
@app.post("/extract_recipe", response_model=ExtractResponse)
async def extract_recipe(req: ExtractRequest) -> ExtractResponse:
    url = req.url.strip()
    logger.info("[FLOW] extract_recipe START | url=%s", url)

    # 1) Fetch
    try:
        html, diag, text_primary = await fetch_html(url)
    except Exception as e:
        msg = f"Fetch failed for {url}: {e}"
        logger.warning(msg)
        return ExtractResponse(ok=False, error=msg,
                               diagnostics={"domain": _domain(url), "fetch_error": str(e)})

    # 2) Visible text
    page_text = text_primary or html_to_visible_text(html)
    if not page_text or len(page_text) < 80:
        msg = "Page has too little visible text to extract."
        logger.warning(msg)
        return ExtractResponse(ok=False, error=msg,
                               diagnostics={"domain": _domain(url), "fetch": diag.get("fetch")})

    # 3) LLM Structured Outputs
    try:
        data = await gemini_structured_extract(url, page_text)
        if isinstance(data, dict) and data.get("error") == "no_recipe":
            return ExtractResponse(ok=False, error="no_recipe",
                                   diagnostics={"domain": _domain(url), **diag})

        recipe = RecipeModel(
            title=clean_text(data.get("title", "")),
            description=clean_text(data.get("description", "")),
            ingredients=[clean_text(x) for x in data.get("ingredients", []) if isinstance(x, str) and clean_text(x)],
            instructions=[clean_text(x) for x in data.get("instructions", []) if isinstance(x, str) and clean_text(x)],
            prepTime=int(data.get("prepTime", 0) or 0),
            cookTime=int(data.get("cookTime", 0) or 0),
            servings=int(data.get("servings", 0) or 0),
            tags=[clean_text(t) for t in data.get("tags", []) if isinstance(t, str) and clean_text(t)],
            imageUrl=clean_text(data.get("imageUrl", "")),
            source=url,
        )

        # 4) Acceptance gate (block placeholders/short outputs)
        bad_title_tokens = {"no recipe found", "not a recipe", "n/a", "recipe"}
        if (not recipe.title or recipe.title.strip().lower() in bad_title_tokens or
            len(recipe.ingredients) < 4 or len(recipe.instructions) < 4):
            logger.warning("[FLOW] LLM returned incomplete fields")
            return ExtractResponse(ok=False, error="LLM returned incomplete fields",
                                   diagnostics={"domain": _domain(url), **diag})

        logger.info("[FLOW] done via LLM | title='%s' ings=%d steps=%d",
                    recipe.title, len(recipe.ingredients), len(recipe.instructions))
        return ExtractResponse(ok=True, recipe=recipe, diagnostics={"domain": _domain(url), **diag})

    except HTTPException as e:
        logger.warning("[LLM] %s", e.detail)
        return ExtractResponse(ok=False, error=e.detail, diagnostics={"domain": _domain(url), **diag})
    except Exception as e:
        logger.exception("[LLM] unexpected failure")
        return ExtractResponse(ok=False, error=f"LLM failure: {e}", diagnostics={"domain": _domain(url), **diag})

# -------------------- Cloud Run entrypoint --------------------
if __name__ == "__main__":
    # Cloud Run requires listening on 0.0.0.0:$PORT
    # (PORT is injected by the platform)
    import uvicorn
    port = int(os.environ.get("PORT", "8080"))
    uvicorn.run("main:app", host="0.0.0.0", port=port, log_level="info", workers=1)
