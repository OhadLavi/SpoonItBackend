"""Shared helpers for Gemini responses and tool/config validation."""

from __future__ import annotations

import json
import re
from typing import Any, Iterable, Optional


def has_google_search_tool(tools: Optional[Iterable[Any]]) -> bool:
    """
    Detect whether a tools list contains Google Search grounding.
    Supports:
      - dict style: {"google_search": {...}}
      - SDK style: types.Tool(google_search=types.GoogleSearch())
    """
    if not tools:
        return False

    for t in tools:
        # dict form
        if isinstance(t, dict) and "google_search" in t:
            return True

        # SDK Tool form (best-effort)
        try:
            if getattr(t, "google_search", None) is not None:
                return True
        except Exception:
            pass

    return False


def extract_first_json_object(text: str) -> str:
    """
    Best-effort extraction of a single JSON object from a model response.
    Helps in cases where model accidentally wraps JSON with prose or code fences.
    """
    t = (text or "").strip()
    if not t:
        return t

    # Remove markdown fences
    t = re.sub(r"^```(?:json)?\s*", "", t, flags=re.IGNORECASE | re.MULTILINE)
    t = re.sub(r"\s*```\s*$", "", t, flags=re.MULTILINE).strip()

    # If already looks like JSON object, return as-is
    if t.startswith("{") and t.endswith("}"):
        return t

    # Otherwise slice from first "{" to last "}"
    i = t.find("{")
    j = t.rfind("}")
    if i != -1 and j != -1 and j > i:
        return t[i : j + 1].strip()

    return t


def get_response_text(response: Any) -> str:
    """
    Robust extraction of text from google-genai responses.
    Prefers `response.text`, but falls back to candidates/content/parts.
    """
    # Preferred
    try:
        t = getattr(response, "text", None)
        if isinstance(t, str) and t.strip():
            return t
    except Exception:
        pass

    # Fallback: candidates -> content -> parts -> text
    try:
        candidates = getattr(response, "candidates", None) or []
        if candidates:
            c0 = candidates[0]
            content = getattr(c0, "content", None)
            parts = getattr(content, "parts", None) or []
            for p in parts:
                pt = getattr(p, "text", None)
                if isinstance(pt, str) and pt.strip():
                    return pt
    except Exception:
        pass

    return ""


def safe_json_loads(text: str) -> dict:
    """
    Parse JSON with tolerant extraction.
    Raises json.JSONDecodeError if still invalid.
    """
    json_text = extract_first_json_object(text)
    return json.loads(json_text)
