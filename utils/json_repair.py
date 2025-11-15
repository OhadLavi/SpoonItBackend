# utils/json_repair.py
"""LLM JSON repair utilities for parsing malformed JSON responses."""

import json
import re
from typing import Any, Dict


def _strip_code_fences(text: str) -> str:
    """Remove markdown code fences / leading 'json' labels."""
    s = text.strip()

    # ```json ... ```
    m = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", s, re.IGNORECASE)
    if m:
        return m.group(1).strip()

    # Generic ``` ... ``` wrappers
    if s.startswith("```"):
        s = s.split("```", 1)[1]
    if s.endswith("```"):
        s = s.rsplit("```", 1)[0]

    # Leading "json\n" label
    if s.lstrip().lower().startswith("json\n"):
        s = s.lstrip()[5:]

    return s.strip()


def _normalize_quotes(text: str) -> str:
    """Normalize various unicode quote characters to standard ASCII quotes."""
    return (
        text.replace("\u201c", '"')
        .replace("\u201d", '"')
        .replace("\u201e", '"')
        .replace("\u00ab", '"')
        .replace("\u00bb", '"')
        .replace("\u2018", "'")
        .replace("\u2019", "'")
        .replace("\u201a", "'")
    )


def _extract_balanced_block(text: str, opener: str, closer: str) -> str | None:
    """Extract a balanced {...} or [...] block starting at the first opener."""
    start = text.find(opener)
    if start == -1:
        return None

    depth = 0
    in_string = False
    escape = False

    for i, ch in enumerate(text[start:], start):
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
        else:
            if ch == '"':
                in_string = True
            elif ch == opener:
                depth += 1
            elif ch == closer:
                depth -= 1
                if depth == 0:
                    return text[start : i + 1]

    return text[start:]


def _extract_json_block(text: str) -> str:
    """Best-effort extraction of the main JSON payload from an LLM response."""
    for opener, closer in (("{", "}"), ("[", "]")):
        block = _extract_balanced_block(text, opener, closer)
        if block is not None:
            return block.strip()
    return text.strip()


def _fix_newlines_inside_strings(s: str) -> str:
    """Replace literal newlines that appear *inside* JSON strings with spaces."""
    out: list[str] = []
    in_string = False
    escape = False

    for ch in s:
        if in_string:
            if escape:
                out.append(ch)
                escape = False
            elif ch == "\\":
                out.append(ch)
                escape = True
            elif ch in ("\n", "\r"):
                out.append(" ")
            elif ch == '"':
                out.append(ch)
                in_string = False
            else:
                out.append(ch)
        else:
            if ch == '"':
                out.append(ch)
                in_string = True
            else:
                out.append(ch)

    return "".join(out)


def _escape_unescaped_inner_quotes(s: str) -> str:
    """Escape suspicious inner quotes inside JSON strings."""
    out: list[str] = []
    in_string = False
    escape = False
    n = len(s)

    i = 0
    while i < n:
        ch = s[i]

        if in_string:
            if escape:
                out.append(ch)
                escape = False
            elif ch == "\\":
                out.append(ch)
                escape = True
            elif ch == '"':
                j = i + 1
                while j < n and s[j].isspace():
                    j += 1

                if j >= n or s[j] in ",}]:":  # looks like closing
                    out.append(ch)
                    in_string = False
                else:  # treat as inner quote
                    out.append("\\")
                    out.append('"')
            else:
                out.append(ch)
        else:
            if ch == '"':
                out.append(ch)
                in_string = True
            else:
                out.append(ch)

        i += 1

    return "".join(out)


def _remove_trailing_commas(s: str) -> str:
    """Remove trailing commas before closing } or ]."""
    return re.sub(r",(\s*[}\]])", r"\1", s)


def _quote_unquoted_keys(s: str) -> str:
    """Quote object keys that look like identifiers but are not quoted."""
    return re.sub(
        r'(?<=[{,])\s*([A-Za-z_][A-Za-z0-9_\-]*)\s*:',
        lambda m: f'"{m.group(1)}":',
        s,
    )


def _collapse_whitespace(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def _repair_and_load(output: str) -> Dict[str, Any]:
    """Core repair pipeline used by both sync and async entrypoints."""
    s = _strip_code_fences(output)
    s = _normalize_quotes(s)
    s = _extract_json_block(s)

    s = _fix_newlines_inside_strings(s)
    s = _escape_unescaped_inner_quotes(s)
    s = _remove_trailing_commas(s)

    try:
        return json.loads(s)
    except json.JSONDecodeError:
        pass

    s2 = _quote_unquoted_keys(s)
    s2 = _escape_unescaped_inner_quotes(s2)
    s2 = _remove_trailing_commas(s2)
    s2 = _collapse_whitespace(s2)

    return json.loads(s2)


async def extract_and_parse_llm_json(output: str) -> Dict[str, Any]:
    """Extract and parse JSON from LLM output with multiple repair strategies."""
    return _repair_and_load(output)
