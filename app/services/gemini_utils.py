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
        if isinstance(t, dict) and "google_search" in t:
            return True
        try:
            if getattr(t, "google_search", None) is not None:
                return True
        except Exception:
            pass

    return False


def extract_balanced_json_object(text: str) -> str:
    """
    Extract the first balanced JSON object {...} from a string.
    Handles braces inside strings and escaped quotes.

    This is more robust than slicing from first '{' to last '}'.
    """
    s = (text or "").strip()
    if not s:
        return s

    # Remove markdown fences (common failure mode)
    s = re.sub(r"^```(?:json)?\s*", "", s, flags=re.IGNORECASE | re.MULTILINE)
    s = re.sub(r"\s*```\s*$", "", s, flags=re.MULTILINE).strip()

    start = s.find("{")
    if start == -1:
        return s

    in_string = False
    escape = False
    depth = 0
    for i in range(start, len(s)):
        ch = s[i]

        if escape:
            escape = False
            continue

        if ch == "\\":
            escape = True
            continue

        if ch == '"':
            in_string = not in_string
            continue

        if in_string:
            continue

        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return s[start : i + 1].strip()

    # If we didn't find a balanced end, return the tail (will likely fail json.loads)
    return s[start:].strip()


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
    json_text = extract_balanced_json_object(text)
    return json.loads(json_text)
