# config.py
"""Configuration settings and logging setup for the Recipe Keeper backend."""

import logging
import os
import re

try:
    import google.generativeai as genai
except ImportError:
    genai = None  # type: ignore

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
PLAYWRIGHT_TIMEOUT_MS = int(os.getenv("PLAYWRIGHT_TIMEOUT_MS", "45000"))
FETCH_MAX_BYTES = 2_500_000
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")

# =============================================================================
# Headers / UA rotation
# =============================================================================
BROWSER_UAS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15",
    "Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Mobile Safari/537.36",
]

# Basic detector for bot/403 blocker pages
BLOCK_PATTERNS = re.compile(
    r"(access\s*denied|forbidden|block(ed)?|request was denied|captcha|just a moment|cloudflare|"
    r"permission\s*denied|not\s*authorized|are you a human|malicious traffic)",
    re.IGNORECASE,
)

# =============================================================================
# Gemini API Configuration
# =============================================================================
if genai and GEMINI_API_KEY:
    try:
        genai.configure(api_key=GEMINI_API_KEY)
    except Exception:
        pass  # Not available or already configured

