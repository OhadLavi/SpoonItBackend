# services/fetcher_service.py
"""HTTP and Playwright-based fetching for recipe pages + Zyte fallback."""

from __future__ import annotations

import asyncio
import os
import random
import re
from typing import Any, Dict, Optional, Tuple

import httpx

from config import (
    BROWSER_UAS,
    BLOCK_PATTERNS,
    HTTP_TIMEOUT,
    PLAYWRIGHT_TIMEOUT_MS,
    ZYTE_API_KEY,
    logger,
)
from errors import APIError

# Lazy Playwright import – container might not have it installed
try:
    from playwright.async_api import async_playwright  # type: ignore
except Exception:  # pragma: no cover
    async_playwright = None  # type: ignore


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _sec_ch_for_ua(ua: str) -> Tuple[str, str, str]:
    is_mobile = "mobile" in ua.lower()
    if "safari" in ua.lower() and "chrome" not in ua.lower():
        sec_ch = '"Not/A)Brand";v="8", "Safari";v="17"'
        platform = '"macOS"'
    elif "android" in ua.lower():
        sec_ch = '"Not/A)Brand";v="8", "Chromium";v="127", "Google Chrome";v="127"'
        platform = '"Android"'
    else:
        sec_ch = '"Not/A)Brand";v="8", "Chromium";v="127", "Google Chrome";v="127"'
        platform = '"Windows"'
    return sec_ch, "?1" if is_mobile else "?0", platform


def _default_headers() -> Dict[str, str]:
    ua = random.choice(BROWSER_UAS)
    sec_ch, sec_mobile, sec_platform = _sec_ch_for_ua(ua)
    return {
        "User-Agent": ua,
        "Accept": (
            "text/html,application/xhtml+xml,application/xml;q=0.9,"
            "image/avif,image/webp,*/*;q=0.8"
        ),
        "Accept-Language": random.choice(
            [
                "he-IL,he;q=0.9,en-US;q=0.8,en;q=0.7",
                "en-US,en;q=0.9,he;q=0.8",
                "en-GB,en;q=0.9",
            ]
        ),
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
        "Connection": "keep-alive",
        "Referer": random.choice(
            ["https://www.google.com/", "https://www.bing.com/", "https://duckduckgo.com/"]
        ),
        "DNT": "1",
        "Sec-Fetch-Dest": "document",
        "Sec-Fetch-Mode": "navigate",
        "Sec-Fetch-Site": "cross-site",
        "Sec-Fetch-User": "?1",
        "sec-ch-ua": sec_ch,
        "sec-ch-ua-mobile": sec_mobile,
        "sec-ch-ua-platform": sec_platform,
        "Upgrade-Insecure-Requests": "1",
    }


def html_to_text(html: str, max_bytes: int = 50_000) -> str:
    """Strip scripts/styles/tags and collapse whitespace."""
    html = re.sub(r"<script\b[^>]*>.*?</script>", "", html, flags=re.DOTALL | re.IGNORECASE)
    html = re.sub(r"<style\b[^>]*>.*?</style>", "", html, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<[^>]+>", " ", html)
    text = re.sub(r"\s+", " ", text)
    encoded = text.encode("utf-8", errors="ignore")
    if len(encoded) > max_bytes:
        text = encoded[:max_bytes].decode("utf-8", errors="ignore")
    return text.strip()


def _looks_blocked(text: str) -> bool:
    """Heuristic to detect bot-blocker / empty responses."""
    if not text:
        return True
    normalized = text.strip()
    if not normalized:
        return True
    if BLOCK_PATTERNS.search(normalized):
        return True
    if len(normalized) < 160:
        alnum_ratio = sum(ch.isalnum() for ch in normalized) / max(len(normalized), 1)
        return alnum_ratio < 0.25
    return False


# ---------------------------------------------------------------------------
# Direct HTTP fetch (httpx)
# ---------------------------------------------------------------------------
async def _httpx_fetch_clean(url: str) -> str:
    async with httpx.AsyncClient(
        timeout=HTTP_TIMEOUT,
        headers=_default_headers(),
        follow_redirects=True,
        http2=True,
    ) as client:
        resp = await client.get(url)
        resp.raise_for_status()
        return html_to_text(resp.text)


# ---------------------------------------------------------------------------
# Jina.ai readability proxy
# ---------------------------------------------------------------------------
def _jina_proxy_url(url: str) -> str:
    normalized = url.strip()
    if not normalized.startswith(("http://", "https://")):
        normalized = f"https://{normalized.lstrip('/')}"
    return f"https://r.jina.ai/{normalized}"


async def _jina_ai_fetch_clean(url: str) -> str:
    proxy_url = _jina_proxy_url(url)
    headers = _default_headers()
    headers["Accept"] = (
        "text/html,application/xhtml+xml,application/xml;q=0.9,"
        "text/plain;q=0.8,*/*;q=0.7"
    )
    async with httpx.AsyncClient(
        timeout=HTTP_TIMEOUT, headers=headers, follow_redirects=True
    ) as client:
        resp = await client.get(proxy_url)
        resp.raise_for_status()
        return html_to_text(resp.text)


# ---------------------------------------------------------------------------
# Playwright dynamic fetch
# ---------------------------------------------------------------------------
async def _playwright_fetch_clean(url: str) -> str:
    if async_playwright is None:
        raise APIError(
            "Playwright not available in this container.",
            status_code=403,
            details={"code": "PLAYWRIGHT_UNAVAILABLE"},
        )

    if os.getenv("DISABLE_PLAYWRIGHT_FETCH", "").lower() in ("1", "true", "yes"):
        raise APIError(
            "Playwright fetch disabled by environment",
            status_code=403,
            details={"code": "PLAYWRIGHT_DISABLED"},
        )

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
            context = await browser.new_context(
                user_agent=random.choice(BROWSER_UAS),
                locale="he-IL",
                extra_http_headers=_default_headers(),
                viewport={"width": 1366, "height": 900},
            )

            await context.route(
                "**/*",
                lambda route: asyncio.create_task(
                    route.abort()
                    if route.request.resource_type
                    in {"image", "media", "font", "stylesheet"}
                    else route.continue_()
                ),
            )

            page = await context.new_page()

            await page.add_init_script(
                """
                Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
                window.chrome = { runtime: {} };
                Object.defineProperty(navigator, 'plugins', { get: () => [1,2,3] });
                Object.defineProperty(navigator, 'languages', { get: () => ['he-IL','he','en-US','en'] });
                """
            )

            for wait_state in ("domcontentloaded", "load", "networkidle"):
                try:
                    await page.goto(url, wait_until=wait_state, timeout=PLAYWRIGHT_TIMEOUT_MS)
                    break
                except Exception:
                    continue

            for _ in range(3):
                await page.mouse.wheel(0, 1200)
                await page.wait_for_timeout(300)

            content_text = ""
            for selector in (
                "main",
                "article",
                "[role='main']",
                ".entry-content",
                ".post-content",
                ".recipe",
                "body",
            ):
                try:
                    el = await page.query_selector(selector)
                    if el:
                        t = await el.inner_text()
                        if t and len(t) > len(content_text):
                            content_text = t
                except Exception:
                    continue

            if not content_text or len(content_text) < 600:
                raw_html = await page.content()
                content_text = html_to_text(raw_html)

            await context.close()
            return content_text
        finally:
            await browser.close()


# ---------------------------------------------------------------------------
# Public: fetch_html_content
# ---------------------------------------------------------------------------
async def fetch_html_content(url: str) -> str:
    """Fetch readable page text using httpx → Playwright → Jina.ai chain."""
    try:
        text = await _httpx_fetch_clean(url)
    except httpx.HTTPStatusError as e:
        status = e.response.status_code if e.response is not None else 0
        logger.warning("[FETCH] httpx status=%s for %s", status, url)
        if status == 403:
            raise APIError(
                "Remote site is blocking server fetch (403).",
                status_code=403,
                details={"code": "FETCH_FORBIDDEN", "url": url},
            )
        raise APIError(
            f"Fetch failed with status {status}.",
            status_code=status,
            details={"code": "FETCH_FAILED", "url": url},
        )
    except httpx.RequestError as e:
        logger.error("[FETCH] httpx request error for %s: %s", url, e, exc_info=True)
        raise APIError(
            "Network error while fetching page.",
            status_code=502,
            details={"code": "FETCH_REQUEST_ERROR", "url": url},
        )

    if not text or _looks_blocked(text):
        logger.info("[FETCH] httpx content looks blocked/short, trying Playwright for %s", url)
        try:
            text = await _playwright_fetch_clean(url)
        except APIError as e:
            logger.warning("[FETCH] Playwright unavailable/disabled: %s", e.message)
            raise
        except Exception as e:
            logger.warning("[FETCH] Playwright error: %s", e, exc_info=True)
            text = ""

    if not text or _looks_blocked(text):
        logger.info("[FETCH] Trying Jina.ai proxy fallback for %s", url)
        try:
            text = await _jina_ai_fetch_clean(url)
        except Exception as e:
            logger.error("[FETCH] Jina.ai proxy failed: %s", e, exc_info=True)
            raise APIError(
                "Remote site is blocking server fetch.",
                status_code=403,
                details={"code": "FETCH_FORBIDDEN", "url": url},
            )

    if _looks_blocked(text):
        raise APIError(
            "Remote site is blocking server fetch.",
            status_code=403,
            details={"code": "FETCH_FORBIDDEN", "url": url},
        )

    logger.info("[FETCH] got %d chars from %s", len(text), url)
    return text


# ---------------------------------------------------------------------------
# Zyte fallback (used only when fetch_html_content fails / 403)
# ---------------------------------------------------------------------------
async def fetch_zyte_article(url: str) -> Dict[str, Any]:
    """Fetch article content from Zyte (article mode) for blocked pages."""
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

    async with httpx.AsyncClient(
        timeout=HTTP_TIMEOUT, auth=(ZYTE_API_KEY, "")
    ) as client:
        try:
            resp = await client.post("https://api.zyte.com/v1/extract", json=payload)
            resp.raise_for_status()
        except httpx.HTTPStatusError as e:
            status_code = e.response.status_code if e.response is not None else 0
            logger.error(
                "[ZYTE] HTTP error for %s: status=%s body_head=%r",
                url,
                status_code,
                (e.response.text[:300] if e.response is not None else ""),
                exc_info=True,
            )
            raise APIError(
                f"Zyte request failed with status {status_code}",
                status_code=502,
                details={"code": "ZYTE_REQUEST_FAILED", "url": url, "http_status": status_code},
            )
        except httpx.RequestError as e:
            logger.error("[ZYTE] Request error for %s: %s", url, e, exc_info=True)
            raise APIError(
                "Zyte request failed",
                status_code=502,
                details={"code": "ZYTE_REQUEST_ERROR", "url": url},
            )

    data = resp.json()
    article = data.get("article") or {}
    if not isinstance(article, dict):
        article = {}

    content = ""
    for key in ("itemMain", "articleBody", "text", "body"):
        val = article.get(key)
        if isinstance(val, str) and val.strip():
            content = val.strip()
            break

    if not content and isinstance(article.get("articleBodyHtml"), str):
        content = html_to_text(article["articleBodyHtml"])

    if not content:
        raise APIError(
            "Zyte did not return usable article content",
            status_code=502,
            details={"code": "ZYTE_NO_CONTENT", "url": url},
        )

    title = (
        article.get("headline")
        or article.get("title")
        or data.get("title")
        or ""
    )
    description = article.get("description") or data.get("description") or ""
    canonical_url = (
        article.get("canonicalUrl")
        or data.get("canonicalUrl")
        or article.get("url")
        or data.get("url")
        or url
    )

    images: list[str] = []

    def _add_image(obj: Any):
        if isinstance(obj, str):
            u = obj.strip()
        elif isinstance(obj, dict):
            u = str(obj.get("url") or obj.get("src") or "").strip()
        else:
            u = ""
        if u and u not in images:
            images.append(u)

    _add_image(article.get("mainImage"))
    raw_images = article.get("images") or []
    if isinstance(raw_images, list):
        for img in raw_images:
            _add_image(img)

    main_image = images[0] if images else ""

    logger.info(
        "[ZYTE] article fetched | len=%d title=%r main_image=%r images=%d",
        len(content),
        title[:60] if title else "",
        main_image,
        len(images),
    )

    return {
        "content": content,
        "title": title or "",
        "description": description or "",
        "url": canonical_url,
        "main_image": main_image,
        "images": images,
    }
