# config.py
"""Configuration settings and logging setup for the Recipe Keeper backend."""

import logging
import os
import re

try:
    import google.generativeai as genai  # type: ignore
except ImportError:  # pragma: no cover
    genai = None  # type: ignore

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

logging.basicConfig(
    level=LOG_LEVEL,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("recipe_keeper.log", encoding="utf-8"),
    ],
)

logger = logging.getLogger("recipe-keeper")

# ---------------------------------------------------------------------------
# HTTP / scraping config
# ---------------------------------------------------------------------------
HTTP_TIMEOUT: float = float(os.getenv("HTTP_TIMEOUT", "30.0"))
PLAYWRIGHT_TIMEOUT_MS: int = int(os.getenv("PLAYWRIGHT_TIMEOUT_MS", "45000"))
FETCH_MAX_BYTES: int = int(os.getenv("FETCH_MAX_BYTES", "2500000"))

# ---------------------------------------------------------------------------
# Gemini config
# ---------------------------------------------------------------------------
GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")
GEMINI_MODEL: str = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")

# ---------------------------------------------------------------------------
# Zyte config (used ONLY as a fetch fallback, not to extract recipes)
# ---------------------------------------------------------------------------
ZYTE_API_KEY: str = os.getenv("ZYTE_API_KEY", "")

# ---------------------------------------------------------------------------
# User agents / block-page heuristics
# ---------------------------------------------------------------------------
BROWSER_UAS = [
    (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/127.0.0.0 Safari/537.36"
    ),
    (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_6) "
        "AppleWebKit/605.1.15 (KHTML, like Gecko) "
        "Version/17.2 Safari/605.1.15"
    ),
    (
        "Mozilla/5.0 (Linux; Android 13; SM-G991B) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/127.0.0.0 Mobile Safari/537.36"
    ),
]

BLOCK_PATTERNS = re.compile(
    r"(access\s*denied|forbidden|block(ed)?|request was denied|captcha|just a moment|"
    r"cloudflare|permission\s*denied|not\s*authorized|are you a human|malicious traffic)",
    re.IGNORECASE,
)

# ---------------------------------------------------------------------------
# Configure Gemini (best-effort)
# ---------------------------------------------------------------------------
if genai and GEMINI_API_KEY:
    try:
        genai.configure(api_key=GEMINI_API_KEY)
    except Exception:  # pragma: no cover
        logger.warning("Failed to configure Gemini API key", exc_info=True)
