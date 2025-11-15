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
        text
        # Curly double quotes
        .replace("\u201c", '"')
        .replace("\u201d", '"')
        # Low double quote
        .replace("\u201e", '"')
        # Angle quotes
        .replace("\u00ab", '"')
        .replace("\u00bb", '"')
        # Curly single quotes
        .replace("\u2018", "'")
        .replace("\u2019", "'")
        # Low single quote
        .replace("\u201a", "'")
    )


def _extract_balanced_block(text: str, opener: str, closer: str) -> str | None:
    """
    Extract a balanced {...} or [...] block starting at the first occurrence
    of `opener`, tracking nested braces and ignoring braces inside strings.
    """
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

    # If we never fully balanced, just return from the opener onward
    return text[start:]


def _extract_json_block(text: str) -> str:
    """
    Best-effort extraction of the main JSON payload from an LLM response.
    Prefers an object, then an array, but otherwise returns the original text.
    """
    for opener, closer in (("{", "}"), ("[", "]")):
        block = _extract_balanced_block(text, opener, closer)
        if block is not None:
            return block.strip()
    return text.strip()


def _fix_newlines_inside_strings(s: str) -> str:
    """
    Replace literal newlines that appear *inside* JSON strings with spaces.

    Example:
        "description": "line 1
        line 2"

    becomes:
        "description": "line 1 line 2"
    """
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
                # Keep JSON valid; for descriptions a space is fine.
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
    """
    Inside JSON strings, escape inner quotes that are very likely to be part
    of the value (e.g. ק"ג) rather than the end of the string.

    Heuristic:
      - While inside a string:
        - If we see a quote (") that is NOT escaped:
          - Look ahead to the next non-space character.
          - If it's one of , } ] : or end-of-text -> treat as closing quote.
          - Otherwise -> treat as inner quote and convert to \".
    """
    out: list[str] = []
    in_string = False
    escape = False
    n = len(s)

    i = 0
    while i < n:
        ch = s[i]

        if in_string:
            if escape:
                # Previous char was a backslash, so this char is escaped.
                out.append(ch)
                escape = False
            elif ch == "\\":
                out.append(ch)
                escape = True
            elif ch == '"':
                # Candidate closing or inner quote
                j = i + 1
                while j < n and s[j].isspace():
                    j += 1

                if j >= n or s[j] in ",}]:":
                    # Looks like a real closing quote
                    out.append(ch)
                    in_string = False
                else:
                    # Looks like an inner quote (e.g. ק"ג) – escape it
                    out.append("\\")
                    out.append('"')
                # Note: don't change `escape` here
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
    """
    Quote object keys that look like identifiers but are not quoted.

    {title: "x"} -> {"title": "x"}
    """
    return re.sub(
        r'(?<=[{,])\s*([A-Za-z_][A-Za-z0-9_\-]*)\s*:',
        lambda m: f'"{m.group(1)}":',
        s,
    )


def _collapse_whitespace(s: str) -> str:
    """Collapse multiple whitespace characters into a single space."""
    return re.sub(r"\s+", " ", s).strip()


def _repair_and_load(output: str) -> Dict[str, Any]:
    """
    Core repair pipeline used by both sync and async entrypoints.
    Raises json.JSONDecodeError if we still can't parse.
    """
    # Basic cleanup: fences, quotes, extract main JSON block
    s = _strip_code_fences(output)
    s = _normalize_quotes(s)
    s = _extract_json_block(s)

    # Fix newlines inside strings and inner quotes
    s = _fix_newlines_inside_strings(s)
    s = _escape_unescaped_inner_quotes(s)
    s = _remove_trailing_commas(s)

    # First, try straight JSON
    try:
        return json.loads(s)
    except json.JSONDecodeError:
        pass

    # Second attempt: quote unquoted keys + collapse whitespace
    s2 = _quote_unquoted_keys(s)
    s2 = _escape_unescaped_inner_quotes(s2)
    s2 = _remove_trailing_commas(s2)
    s2 = _collapse_whitespace(s2)

    return json.loads(s2)


async def extract_and_parse_llm_json(output: str) -> Dict[str, Any]:
    """
    Extract and parse JSON from LLM output with multiple repair strategies.

    This is defined as async so it can be awaited from FastAPI routes, but the
    work is synchronous and CPU-only.
    """
    return _repair_and_load(output)
