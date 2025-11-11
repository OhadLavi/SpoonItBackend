# utils/json_repair.py
"""LLM JSON repair utilities for parsing malformed JSON responses."""

import json
import re


def _strip_code_fences(text: str) -> str:
    """Remove markdown code fences from text."""
    s = text.strip()
    m = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", s, re.IGNORECASE)
    if m:
        return m.group(1).strip()
    if s.startswith("```"):
        s = s.split("```", 1)[1]
    if s.endswith("```"):
        s = s.rsplit("```", 1)[0]
    if s.lstrip().lower().startswith("json\n"):
        s = s.lstrip()[5:]
    return s.strip()


def _normalize_quotes(text: str) -> str:
    """Normalize various quote characters to standard quotes."""
    return (
        text.replace("\u201c", '"').replace("\u201d", '"')
        .replace("\u2018", "'").replace("\u2019", "'")
        .replace(""", '"').replace(""", '"').replace("'", "'").replace("'", "'")
    )


def _remove_trailing_commas(s: str) -> str:
    """Remove trailing commas before closing braces/brackets."""
    return re.sub(r",(\s*[}\]])", r"\1", s)


def _quote_unquoted_keys(s: str) -> str:
    """Add quotes around unquoted object keys."""
    return re.sub(r'(?<=[{,])\s*([A-Za-z_][A-Za-z0-9_\-]*)\s*:', r'"\1":', s)


def _quote_unquoted_string_values(s: str) -> str:
    """Add quotes around unquoted string values."""
    s = re.sub(
        r'(:\s*)(?!-?\d+(?:\.\d+)?\b)(?!true\b|false\b|null\b)(?!\"|\{|\[)([^,\}\]]+)',
        lambda m: m.group(1) + '"' + m.group(2).strip().replace('"', '\\"') + '"',
        s, flags=re.IGNORECASE,
    )
    s = re.sub(
        r'(?:(?<=\[)|(?<=,))\s*(?!-?\d+(?:\.\d+)?\b)(?!true\b|false\b|null\b)(?!\"|\{|\[)([^,\]\}]+)\s*(?=,|\])',
        lambda m: ' "' + m.group(1).strip().replace('"', '\\"') + '"',
        s, flags=re.IGNORECASE,
    )
    return s


def _collapse_whitespace(s: str) -> str:
    """Collapse multiple whitespace characters to single space."""
    return re.sub(r"\s+", " ", s).strip()


async def extract_and_parse_llm_json(output: str) -> dict:
    """Extract and parse JSON from LLM output with multiple repair strategies."""
    s = _strip_code_fences(_normalize_quotes(output))
    s = _remove_trailing_commas(_quote_unquoted_keys(s))
    try:
        return json.loads(s)
    except json.JSONDecodeError:
        pass
    s2 = _quote_unquoted_string_values(s)
    s2 = _remove_trailing_commas(s2)
    try:
        return json.loads(s2)
    except json.JSONDecodeError:
        s3 = _collapse_whitespace(s2)
        s3 = _remove_trailing_commas(s3)
        return json.loads(s3)

