"""Web extraction service using Gemini url_context with structured JSON output."""

from __future__ import annotations

import logging
from typing import Any, Dict, Optional

from google import genai
from google.genai import types
from pydantic import ValidationError

from app.config import settings
from app.models.recipe import Recipe
from app.utils.exceptions import ScrapingError
from app.services.gemini_utils import get_response_text, safe_json_loads

logger = logging.getLogger(__name__)


class ScraperService:
    """Service for extracting recipe content from URLs using Gemini url_context."""

    def __init__(self):
        self._client: Optional[genai.Client] = None
        self._recipe_schema: Dict[str, Any] = Recipe.model_json_schema()

    @property
    def client(self) -> genai.Client:
        if self._client is None:
            self._client = genai.Client(api_key=settings.gemini_api_key)
        return self._client

    async def extract_recipe_from_url(self, url: str) -> Recipe:
        prompt = self._build_url_extraction_prompt(url)

        try:
            response = await self.client.aio.models.generate_content(
                model="gemini-2.5-flash",
                contents=prompt,
                config=types.GenerateContentConfig(
                    tools=[{"url_context": {}}],
                    response_mime_type="application/json",
                    response_json_schema=self._recipe_schema,
                    temperature=0.0,
                    max_output_tokens=4096,
                ),
            )

            response_text = get_response_text(response)
            if not response_text.strip():
                # Optional metadata for debugging
                meta = None
                try:
                    meta = response.candidates[0].url_context_metadata  # type: ignore[attr-defined]
                except Exception:
                    meta = None
                raise ScrapingError(f"Gemini returned empty response for url_context. metadata={meta}")

            data = safe_json_loads(response_text)
            data = self._normalize_recipe_json(data, source_url=url)

            recipe = Recipe.model_validate(data)
            if not recipe.title or len(recipe.ingredients) == 0:
                raise ScrapingError("Extracted recipe is empty/invalid (missing title or ingredients).")

            return recipe

        except (ValidationError, ValueError) as e:
            logger.error(f"url_context JSON parse/validation failed: {str(e)}", exc_info=True)
            raise ScrapingError(f"Failed to parse recipe JSON from url_context: {str(e)}") from e
        except Exception as e:
            logger.error(f"Recipe extraction from URL failed: {str(e)}", exc_info=True)
            raise ScrapingError(f"Failed to extract recipe from URL: {str(e)}") from e

    def _build_url_extraction_prompt(self, url: str) -> str:
        return f"""יש לך גישה לתוכן העמוד באמצעות url_context עבור ה-URL הבא:
{url}

מטרה: להחזיר אובייקט JSON תקין לפי הסכימה שסופקה (Recipe), שמכיל רק את המתכון.

כללים נוקשים:
- שמור על טקסט מדויק של המרכיבים כפי שמופיע בעמוד (raw). אל תתרגם, אל תנרמל, אל תשנה יחידות/כמויות.
- אל תמציא מרכיבים/שלבים שלא קיימים בעמוד.
- אם מידע לא מופיע: null לשדות אופציונליים, [] לרשימות.
- מלא גם ingredientGroups וגם ingredients.
- מלא גם instructionGroups וגם instructions (לפי הסדר).
- notes: כל טיפים/המלצות/הערות שמופיעים בעמוד.
- imageUrl: כתובת מלאה (http/https) אם קיימת, אחרת null. images: רשימת URLים לתמונות אם קיימת, אחרת [].
החזר JSON בלבד. ללא הסברים. ללא markdown.
"""

    def _normalize_recipe_json(self, recipe_json: Dict[str, Any], source_url: str) -> Dict[str, Any]:
        normalized: Dict[str, Any] = dict(recipe_json or {})
        normalized["source"] = source_url

        for k in ("ingredientGroups", "ingredients", "instructionGroups", "instructions", "notes", "images"):
            if normalized.get(k) is None:
                normalized[k] = []

        if "servings" in normalized and normalized["servings"] is not None and not isinstance(normalized["servings"], str):
            normalized["servings"] = str(normalized["servings"])

        img = normalized.get("imageUrl")
        if isinstance(img, str):
            s = img.strip()
            if not s or not s.startswith(("http://", "https://")):
                normalized["imageUrl"] = None

        imgs = normalized.get("images")
        if isinstance(imgs, list):
            normalized["images"] = [x for x in imgs if isinstance(x, str) and x.strip()]

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
