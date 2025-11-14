# services/fetcher_service.py
"""HTTP and Playwright fetching services for web scraping."""

import asyncio
import os
import random
import re
from typing import Optional, Tuple

import httpx

from config import (
    logger,
    HTTP_TIMEOUT,
    PLAYWRIGHT_TIMEOUT_MS,
    BROWSER_UAS,
    BLOCK_PATTERNS,
)
from errors import APIError

# --- Safe/lazy Playwright import (prevents NameError if lib missing) ---
try:
    from playwright.async_api import async_playwright  # type: ignore
except Exception:
    async_playwright = None  # will be checked at runtime


_ACCEPT_LANGS = [
    "he-IL,he;q=0.9,en-US;q=0.8,en;q=0.7",
    "en-US,en;q=0.9,he;q=0.8",
    "en-GB,en;q=0.9",
]

_REFERERS = [
    "https://www.google.com/",
    "https://www.bing.com/",
    "https://duckduckgo.com/",
]


def _sec_ch_for_ua(ua: str) -> Tuple[str, str, str]:
    """Return sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform headers."""

    is_mobile = "mobile" in ua.lower()
    if "safari" in ua.lower() and "chrome" not in ua.lower():
        sec_ch = '"Not/A)Brand";v="8", "Safari";v="17"'
        platform = '"macOS"'
    elif "android" in ua.lower():
        sec_ch = '"Not/A)Brand";v="8", "Chromium";v="127", "Google Chrome";v="127"'
        platform = '"Android"'
    elif "mac os" in ua.lower():
        sec_ch = '"Not/A)Brand";v="8", "Chromium";v="127", "Google Chrome";v="127"'
        platform = '"macOS"'
    else:
        sec_ch = '"Not/A)Brand";v="8", "Chromium";v="127", "Google Chrome";v="127"'
        platform = '"Windows"'

    return sec_ch, "?1" if is_mobile else "?0", platform


def _default_headers() -> dict:
    """Generate default HTTP headers with random user agent."""

    ua = random.choice(BROWSER_UAS)
    sec_ch, sec_mobile, sec_platform = _sec_ch_for_ua(ua)
    return {
        "User-Agent": ua,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": random.choice(_ACCEPT_LANGS),
        "Accept-Encoding": "gzip, deflate, br",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
        "Connection": "keep-alive",
        "Referer": random.choice(_REFERERS),
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


def _looks_blocked(text: str) -> bool:
    """Check if response looks like a bot blocker page with looser heuristics."""

    if not text:
        return True

    normalized = text.strip()
    if not normalized:
        return True

    if BLOCK_PATTERNS.search(normalized):
        return True

    # Previously we flagged every short response as blocked which produced
    # false positives for minimalist recipe pages. Only treat extremely short
    # snippets as blocked when there is no meaningful content at all.
    if len(normalized) < 160:
        alnum_ratio = sum(ch.isalnum() for ch in normalized) / max(len(normalized), 1)
        return alnum_ratio < 0.25

    return False


async def _httpx_fetch(url: str) -> str:
    """Fetch HTML content using httpx."""
    async with httpx.AsyncClient(
        timeout=HTTP_TIMEOUT,
        headers=_default_headers(),
        follow_redirects=True,
        http2=True,
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
    """Fetch HTML content using Playwright for JavaScript-heavy sites."""
    # If Playwright is not installed or import failed, report a structured 403
    if async_playwright is None:
        raise APIError(
            "Playwright not available in this container.",
            status_code=403,
            details={"code": "PLAYWRIGHT_UNAVAILABLE", "hint": "Install playwright & browsers in the image"},
        )

    if os.getenv("DISABLE_PLAYWRIGHT_FETCH", "").lower() in ("1", "true", "yes"):
        raise RuntimeError("Playwright fetch disabled by env")

    per_try_timeout_ms = PLAYWRIGHT_TIMEOUT_MS
    max_retries = 2  # total tries = 3

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
            last_error: Optional[Exception] = None
            for attempt in range(max_retries + 1):
                context = await browser.new_context(
                    user_agent=random.choice(BROWSER_UAS),
                    locale="he-IL",
                    extra_http_headers=_default_headers(),
                    bypass_csp=True,
                    viewport={"width": 1366, "height": 900},
                )

                # Block heavy resources to avoid 'networkidle' never completing
                await context.route(
                    "**/*",
                    lambda route: asyncio.create_task(
                        route.abort()
                        if route.request.resource_type in {"image", "media", "font", "stylesheet"}
                        else route.continue_()
                    ),
                )

                page = await context.new_page()

                # light stealth
                await page.add_init_script("""
                    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
                    window.chrome = { runtime: {} };
                    Object.defineProperty(navigator, 'plugins', { get: () => [1,2,3] });
                    Object.defineProperty(navigator, 'languages', { get: () => ['he-IL','he','en-US','en'] });
                """)

                # Prefer DOM readiness chain over strict 'networkidle' (often never reached).
                for wu in ("domcontentloaded", "load", "networkidle"):
                    try:
                        await page.goto(url, wait_until=wu, timeout=per_try_timeout_ms)
                        break
                    except Exception as e:
                        last_error = e
                else:
                    await context.close()
                    raise last_error or TimeoutError("page.goto failed for all wait states")

                # Element-based readiness (more reliable than global load state)
                try:
                    await page.wait_for_selector("main, article, [role='main'], .entry-content, .post-content, .recipe, body", timeout=3000)
                except Exception:
                    pass

                # Scroll to trigger lazy content
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

                # Fallback to stripped HTML
                if len(content_text or "") < 600:
                    raw_html = await page.content()
                    raw_html = re.sub(r'<script[^>]*>.*?</script>', '', raw_html, flags=re.DOTALL | re.IGNORECASE)
                    raw_html = re.sub(r'<style[^>]*>.*?</style>', '', raw_html, flags=re.DOTALL | re.IGNORECASE)
                    content_text = re.sub(r'<[^>]+>', ' ', raw_html)

                text = re.sub(r"\s+", " ", (content_text or "")).strip()
                if len(text.encode("utf-8")) > 50_000:
                    text = text[:50_000]

                # If body still looks like a block page, try cookie-sharing API request.
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

            raise APIError("Playwright retries exhausted", status_code=504)
        finally:
            await browser.close()


async def fetch_html_content(url: str) -> str:
    """Fetch HTML content from URL with automatic fallback to Playwright if blocked."""
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

