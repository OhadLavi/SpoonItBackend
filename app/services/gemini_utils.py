"""Shared helpers for Gemini responses, parsing, and debugging."""

from __future__ import annotations

import json
import logging
import re
from typing import Any, Dict, Iterable, Optional

logger = logging.getLogger(__name__)


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
        if isinstance(t, dict) and "google_search" in t:
            return True
        try:
            if getattr(t, "google_search", None) is not None:
                return True
        except Exception:
            pass

    return False


def extract_first_json_value(text: str) -> str:
    """
    Best-effort extraction of a single JSON object/array from a model response.

    Handles:
    - markdown fences
    - leading/trailing prose
    - trailing garbage
    """
    t = (text or "").strip()
    if not t:
        return t

    # Remove markdown fences
    t = re.sub(r"^```(?:json)?\s*", "", t, flags=re.IGNORECASE | re.MULTILINE)
    t = re.sub(r"\s*```\s*$", "", t, flags=re.MULTILINE).strip()

    # If it already looks like JSON
    if (t.startswith("{") and t.endswith("}")) or (t.startswith("[") and t.endswith("]")):
        return t

    # Slice from first "{" or "[" to last matching closing brace/bracket (best effort)
    first_obj = t.find("{")
    first_arr = t.find("[")
    if first_obj == -1 and first_arr == -1:
        return t

    start = first_obj
    if start == -1 or (first_arr != -1 and first_arr < start):
        start = first_arr

    # Very tolerant: take from start to last '}' or ']' whichever is later
    end_obj = t.rfind("}")
    end_arr = t.rfind("]")
    end = max(end_obj, end_arr)

    if end > start:
        return t[start : end + 1].strip()

    return t


def _strip_trailing_commas(json_text: str) -> str:
    # Converts: {"a": 1,} -> {"a": 1}
    # and: [1,2,] -> [1,2]
    return re.sub(r",(\s*[}\]])", r"\1", json_text)


def safe_json_loads(text: str) -> dict:
    """
    Parse JSON with tolerant extraction and a tiny local "repair" (trailing commas).
    Raises json.JSONDecodeError if still invalid.
    """
    json_text = extract_first_json_value(text)
    json_text = json_text.strip()

    try:
        return json.loads(json_text)
    except json.JSONDecodeError:
        repaired = _strip_trailing_commas(json_text)
        return json.loads(repaired)


def get_response_text(response: Any) -> str:
    """
    Robust extraction of text from google-genai responses.

    Tries:
    1) response.text
    2) response.parts[*].text  (SDK exposes response.parts in many examples)
    3) response.candidates[0].content.parts[*].text
    4) dict-like fallbacks
    """
    # 1) Preferred
    try:
        t = getattr(response, "text", None)
        if isinstance(t, str) and t.strip():
            return t
    except Exception:
        pass

    # 2) response.parts
    try:
        parts = getattr(response, "parts", None) or []
        for p in parts:
            pt = getattr(p, "text", None)
            if isinstance(pt, str) and pt.strip():
                return pt
            # dict style
            if isinstance(p, dict):
                pt2 = p.get("text")
                if isinstance(pt2, str) and pt2.strip():
                    return pt2
    except Exception:
        pass

    # 3) candidates -> content -> parts
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
                if isinstance(p, dict):
                    pt2 = p.get("text")
                    if isinstance(pt2, str) and pt2.strip():
                        return pt2
    except Exception:
        pass

    return ""


def response_debug_summary(response: Any) -> Dict[str, Any]:
    """
    Safe, compact debug info (no huge dumps).
    Helps explain "HTTP 200 but empty text".
    """
    out: Dict[str, Any] = {}

    try:
        out["has_text_prop"] = hasattr(response, "text")
        t = getattr(response, "text", None)
        out["text_len"] = len(t) if isinstance(t, str) else None
    except Exception:
        out["text_len"] = None

    # candidates info
    try:
        candidates = getattr(response, "candidates", None) or []
        out["candidates"] = len(candidates)
        if candidates:
            c0 = candidates[0]
            out["finish_reason"] = getattr(c0, "finish_reason", None)

            # safety ratings (structure varies)
            out["safety_ratings"] = getattr(c0, "safety_ratings", None)

            # url_context metadata (if present)
            out["url_context_metadata"] = getattr(c0, "url_context_metadata", None)

            # grounding metadata (google_search)
            out["grounding_metadata"] = getattr(c0, "grounding_metadata", None)

            # parts count
            content = getattr(c0, "content", None)
            parts = getattr(content, "parts", None) or []
            out["parts"] = len(parts)
    except Exception:
        pass

    return out


def log_empty_response(prefix: str, response: Any) -> None:
    summary = response_debug_summary(response)
    logger.warning(f"{prefix} empty response text. summary={summary}")
