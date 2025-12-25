"""Web extraction service using Gemini url_context with structured JSON output."""

import json
import logging
import re
from typing import Any, Dict, Optional

from google import genai
from google.genai import types
from pydantic import ValidationError

from app.config import settings
from app.models.recipe import Recipe
from app.utils.exceptions import ScrapingError

logger = logging.getLogger(__name__)


def _extract_first_json_object(text: str) -> str:
    """
    Best-effort: if model returned extra text (shouldn't with structured outputs),
    try to slice the first JSON object.
    """
    t = (text or "").strip()
    if not t:
        return t

    # Remove common fenced blocks
    t = re.sub(r"^```(?:json)?\s*", "", t, flags=re.MULTILINE)
    t = re.sub(r"\s*```\s*$", "", t, flags=re.MULTILINE).strip()

    # If already starts with {, assume it's JSON
    if t.startswith("{") and t.endswith("}"):
        return t

    # Otherwise, take substring between first '{' and last '}'.
    i = t.find("{")
    j = t.rfind("}")
    if i != -1 and j != -1 and j > i:
        return t[i : j + 1].strip()

    return t


def _get_response_text(response: Any) -> str:
    """
    google-genai responses usually expose `response.text`.
    This is a robust fallback in case `text` is missing/empty.
    """
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


class ScraperService:
    """Service for extracting recipe content from URLs using Gemini url_context."""

    def __init__(self):
        self._client: Optional[genai.Client] = None
        # Pydantic v2: JSON Schema dict that Gemini can use for structured outputs
        self._recipe_schema: Dict[str, Any] = Recipe.model_json_schema()

    @property
    def client(self) -> genai.Client:
        """Lazy init Gemini client."""
        if self._client is None:
            self._client = genai.Client(api_key=settings.gemini_api_key)
        return self._client

    async def extract_recipe_from_url(self, url: str) -> Recipe:
        """
        Single-call extraction:
        - Gemini fetches the page via url_context
        - Gemini returns STRICT JSON by response_json_schema (Recipe schema)
        """
        prompt = self._build_url_extraction_prompt(url)

        try:
            logger.info(f"Extracting recipe from URL (structured): {url}")

            response = await self.client.aio.models.generate_content(
                model="gemini-2.5-flash",
                contents=prompt,
                config=types.GenerateContentConfig(
                    tools=[{"url_context": {}}],
                    response_mime_type="application/json",
                    response_json_schema=self._recipe_schema,
                    temperature=0,
                ),
            )

            response_text = _get_response_text(response)
            if not response_text.strip():
                # Helpful metadata for debugging URL fetch issues (if present)
                meta = None
                try:
                    meta = response.candidates[0].url_context_metadata  # type: ignore[attr-defined]
                except Exception:
                    meta = None
                logger.error(f"Gemini returned empty response for URL. url_context_metadata={meta}")
                raise ScrapingError("Gemini returned empty response (no JSON).")

            logger.debug(f"Gemini structured JSON (first 500 chars): {response_text[:500]}")

            json_text = _extract_first_json_object(response_text)
            data = json.loads(json_text)

            data = self._normalize_recipe_json(data, source_url=url)

            recipe = Recipe.model_validate(data)

            # Validate “meaningful”
            if not recipe.title or len(recipe.ingredients) == 0:
                raise ScrapingError(
                    "Extracted recipe is empty/invalid (missing title or ingredients)."
                )

            return recipe

        except (json.JSONDecodeError, ValidationError) as e:
            logger.error(f"Structured JSON parsing/validation failed: {str(e)}", exc_info=True)
            raise ScrapingError(f"Failed to parse structured recipe JSON: {str(e)}") from e
        except Exception as e:
            logger.error(f"Recipe extraction from URL failed: {str(e)}", exc_info=True)
            raise ScrapingError(f"Failed to extract recipe from URL: {str(e)}") from e

    def _build_url_extraction_prompt(self, url: str) -> str:
        """
        IMPORTANT:
        With response_json_schema, Gemini is constrained to your Recipe schema.
        The prompt here focuses on *content rules* (exact raw text, no inventions).
        """
        return f"""יש לך גישה לתוכן העמוד באמצעות url_context עבור ה-URL הבא:
{url}

מטרה: להחזיר אובייקט JSON תקין לפי הסכימה שסופקה (Recipe), שמכיל רק את המתכון.

כללים נוקשים:
- שמור על טקסט מדויק של המרכיבים כפי שמופיע בעמוד (raw). אל תתרגם, אל תנרמל, אל תשנה יחידות/כמויות.
- אל תמציא מרכיבים/שלבים שלא קיימים בעמוד.
- אם מידע לא מופיע:
  - לשדות אופציונליים השתמש ב-null
  - לרשימות השתמש ב-[] (או השאר ריק לפי הסכימה)
- מלא גם ingredientGroups וגם ingredients (רשימה שטוחה של raw).
- מלא גם instructionGroups וגם instructions (רשימה שטוחה לפי הסדר).
- notes: כל טיפים/המלצות/הערות שמופיעים בעמוד.
- imageUrl: כתובת מלאה (http/https) אם קיימת, אחרת null. images: רשימת URLים לתמונות אם קיימת, אחרת [].

החזר JSON בלבד. ללא הסברים. ללא markdown.
"""

    def _normalize_recipe_json(self, recipe_json: Dict[str, Any], source_url: str) -> Dict[str, Any]:
        """
        Make output robust to minor model deviations while still matching your Recipe model.
        """
        normalized: Dict[str, Any] = dict(recipe_json or {})

        # Always set source to requested URL (authoritative)
        normalized["source"] = source_url

        # Ensure list fields are at least lists (your model uses default_factory=list)
        for k in ("ingredientGroups", "ingredients", "instructionGroups", "instructions", "notes", "images"):
            if normalized.get(k) is None:
                normalized[k] = []

        # servings should be string if provided
        if "servings" in normalized and normalized["servings"] is not None and not isinstance(normalized["servings"], str):
            normalized["servings"] = str(normalized["servings"])

        # imageUrl: if invalid/empty -> None (HttpUrl validation is strict)
        img = normalized.get("imageUrl")
        if isinstance(img, str):
            s = img.strip()
            if not s or not s.startswith(("http://", "https://")):
                normalized["imageUrl"] = None

        # images: remove empties
        imgs = normalized.get("images")
        if isinstance(imgs, list):
            normalized["images"] = [x for x in imgs if isinstance(x, str) and x.strip()]

        # ingredientGroups: tolerate "ingredients": ["..."] by converting to [{"raw": "..."}]
        ig = normalized.get("ingredientGroups")
        if isinstance(ig, list):
            fixed_groups = []
            for g in ig:
                if not isinstance(g, dict):
                    continue
                ingr = g.get("ingredients")
                if isinstance(ingr, list) and ingr and all(isinstance(x, str) for x in ingr):
                    g = dict(g)
                    g["ingredients"] = [{"raw": x} for x in ingr if x.strip()]
                fixed_groups.append(g)
            normalized["ingredientGroups"] = fixed_groups

        return normalized
