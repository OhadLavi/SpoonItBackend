# services/gemini_service.py
"""Gemini API service wrapper."""

from __future__ import annotations

import asyncio
from typing import Any, Dict

try:
    import google.generativeai as genai  # type: ignore
except ImportError:  # pragma: no cover
    genai = None  # type: ignore

from config import GEMINI_API_KEY, GEMINI_MODEL, logger
from errors import APIError
from utils.json_repair import extract_and_parse_llm_json


def get_gemini_model() -> Any:
    """Get configured Gemini model instance."""
    if genai is None:
        raise APIError(
            "google-generativeai package is not installed",
            status_code=500,
            details={"code": "GEMINI_NOT_INSTALLED"},
        )
    if not GEMINI_API_KEY:
        raise APIError(
            "GEMINI_API_KEY not configured",
            status_code=500,
            details={"code": "GEMINI_API_KEY_MISSING"},
        )
    return genai.GenerativeModel(GEMINI_MODEL)


async def generate_json_from_prompt(
    prompt: str,
    *,
    max_output_tokens: int = 4096,
    temperature: float = 0.0,
    label: str = "json",
) -> Dict[str, Any]:
    """Call Gemini and parse the result as JSON using the repair helper."""
    model = get_gemini_model()

    def _call():
        return model.generate_content(
            prompt,
            generation_config={
                "temperature": temperature,
                "top_p": 0.9,
                "top_k": 32,
                "max_output_tokens": max_output_tokens,
                "response_mime_type": "application/json",
            },
        )

    try:
        response = await asyncio.to_thread(_call)
    except Exception as e:  # pragma: no cover
        logger.error("[GEMINI][%s] API error: %s", label, e, exc_info=True)
        raise APIError(
            "Error calling Gemini API",
            status_code=502,
            details={"code": "LLM_ERROR", "label": label},
        )

    text = (getattr(response, "text", None) or "").strip()
    if not text:
        logger.error("[GEMINI][%s] Empty response", label)
        raise APIError(
            "Model returned empty response",
            status_code=502,
            details={"code": "LLM_EMPTY", "label": label},
        )

    try:
        return await extract_and_parse_llm_json(text)
    except Exception as e:
        logger.error(
            "[GEMINI][%s] JSON parse failed: %s | head=%r",
            label,
            e,
            text[:400],
            exc_info=True,
        )
        raise APIError(
            "Failed to parse JSON from Gemini",
            status_code=502,
            details={"code": "LLM_JSON_PARSE", "label": label, "raw_head": text[:400]},
        )


async def generate_text_from_prompt(
    prompt: str,
    *,
    max_output_tokens: int = 2048,
    temperature: float = 0.5,
    label: str = "text",
) -> str:
    """Plain-text generation helper (not used for recipe extraction)."""
    model = get_gemini_model()

    def _call():
        return model.generate_content(
            prompt,
            generation_config={
                "temperature": temperature,
                "top_p": 0.9,
                "top_k": 32,
                "max_output_tokens": max_output_tokens,
            },
        )

    try:
        response = await asyncio.to_thread(_call)
    except Exception as e:  # pragma: no cover
        logger.error("[GEMINI][%s] API error: %s", label, e, exc_info=True)
        raise APIError(
            "Error calling Gemini API",
            status_code=502,
            details={"code": "LLM_ERROR", "label": label},
        )

    text = (getattr(response, "text", None) or "").strip()
    if not text:
        raise APIError(
            "Model returned empty response",
            status_code=502,
            details={"code": "LLM_EMPTY", "label": label},
        )
    return text
