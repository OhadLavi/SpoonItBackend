# services/gemini_service.py
"""Gemini API service wrapper."""

try:
    import google.generativeai as genai  # type: ignore
except ImportError:
    genai = None  # type: ignore

from config import GEMINI_API_KEY, GEMINI_MODEL, logger

# Configure Gemini API (if not already configured in config.py)
if genai and GEMINI_API_KEY:
    try:
        genai.configure(api_key=GEMINI_API_KEY)
    except Exception:
        pass  # Already configured or not available


def get_gemini_model():
    """Get configured Gemini model instance."""
    if genai is None:
        raise ImportError("google-generativeai package is not installed. Install it with: pip install google-generativeai")
    return genai.GenerativeModel(GEMINI_MODEL)


async def generate_content(prompt: str) -> str:
    """Generate content using Gemini API."""
    try:
        model = get_gemini_model()
        response = model.generate_content(prompt)
        return (response.text or "").strip()
    except Exception as e:
        logger.error("[GEMINI] API error: %s", e, exc_info=True)
        raise

