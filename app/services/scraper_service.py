"""Web extraction service using Gemini url_context (tool) with JSON-as-text output."""

from __future__ import annotations

import logging
from typing import Any, Dict, Optional

from google import genai
from google.genai import types
from pydantic import ValidationError

from app.config import settings
from app.models.recipe import Recipe
from app.utils.exceptions import ScrapingError
from app.services.gemini_utils import (
    get_response_text,
    log_empty_response,
    safe_json_loads,
)

logger = logging.getLogger(__name__)


class ScraperService:
    """
    IMPORTANT:
    Gemini 2.5 Flash does NOT support tool-use with response_mime_type=application/json.
    So we ask for text/plain and force the model to output JSON as text.
    """

    def __init__(self):
        self._client: Optional[genai.Client] = None
        self._recipe_schema: Dict[str, Any] = Recipe.model_json_schema()

    @property
    def client(self) -> genai.Client:
        if self._client is None:
            self._client = genai.Client(api_key=settings.gemini_api_key)
        return self._client

    async def extract_recipe_from_url(self, url: str) -> Recipe:
        """
        Single-call attempt:
          url_context tool + text/plain + JSON-as-text

        If JSON parsing/validation fails, we do a repair call WITHOUT tools using structured output schema.
        """
        prompt = self._build_url_context_json_prompt(url)

        # retries help with flakiness/tool retrieval issues
        last_text = ""
        for attempt in range(1, 3):
            try:
                response = await self.client.aio.models.generate_content(
                    model="gemini-2.5-flash",
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        tools=[{"url_context": {}}],
                        response_mime_type="text/plain",
                        temperature=0.0,
                        max_output_tokens=4096,
                    ),
                )

                text = get_response_text(response).strip()
                last_text = text

                if not text:
                    log_empty_response(f"url_context returned empty text (attempt {attempt}/2).", response)
                    continue

                data = safe_json_loads(text)
                data = self._normalize_recipe_json(data, source_url=url)
                recipe = Recipe.model_validate(data)

                if not recipe.title or len(recipe.ingredients) == 0:
                    raise ScrapingError("Extracted recipe is empty/invalid (missing title or ingredients).")

                return recipe

            except (ValueError, ValidationError) as e:
                logger.warning(
                    f"url_context JSON parse/validation failed (attempt {attempt}/2): {str(e)}",
                    exc_info=True,
                )
                # try structured repair once (no tools)
                try:
                    repaired = await self._repair_to_schema(last_text, source_url=url)
                    return repaired
                except Exception:
                    # continue retry loop for tool call
                    continue
            except Exception as e:
                logger.warning(
                    f"url_context attempt {attempt}/2 failed: {str(e)}",
                    exc_info=True,
                )
                continue

        raise ScrapingError(f"url_context returned empty text after retries. last_text_len={len(last_text)}")

    def _build_url_context_json_prompt(self, url: str) -> str:
        # Keep it explicit and aligned with your Pydantic model fields
        return f"""
יש לך גישה לתוכן העמוד באמצעות url_context עבור ה-URL הבא:
{url}

מטרה: להחזיר אובייקט JSON תקין בלבד, בתבנית המדויקת של Recipe (כמו במודל Pydantic).

כללים נוקשים:
- שמור על טקסט מדויק של המרכיבים כפי שמופיע בעמוד (ingredientGroups.ingredients[].raw + ingredients[]). אל תתרגם, אל תנרמל, אל תשנה יחידות/כמויות.
- אל תמציא מרכיבים/שלבים שלא קיימים בעמוד.
- אם מידע לא מופיע: null לשדות אופציונליים, [] לרשימות.
- מלא גם ingredientGroups וגם ingredients.
- מלא גם instructionGroups וגם instructions (לפי הסדר).
- notes: כל טיפים/המלצות/הערות שמופיעים בעמוד.
- imageUrl: כתובת מלאה (http/https) אם קיימת, אחרת null. images: רשימת URLים לתמונות אם קיימת, אחרת [].
- id/createdAt/updatedAt: null עבור מתכון שחולץ.
- source: שים את ה-URL במחרוזת.

החזר JSON בלבד. ללא markdown. ללא code blocks. ללא הסברים.

תבנית JSON (דוגמה לשדות, לא תוכן):
{{
  "id": null,
  "title": null,
  "description": null,
  "source": "{url}",
  "language": null,
  "servings": null,
  "prepTimeMinutes": null,
  "cookTimeMinutes": null,
  "totalTimeMinutes": null,
  "ingredientGroups": [{{"name": null, "ingredients": [{{"raw": ""}}]}}],
  "ingredients": [""],
  "instructionGroups": [{{"name": null, "instructions": [""]}}],
  "instructions": [""],
  "notes": [],
  "imageUrl": null,
  "images": [],
  "nutrition": {{
    "calories": null,
    "protein_g": null,
    "fat_g": null,
    "carbs_g": null,
    "per": null
  }},
  "createdAt": null,
  "updatedAt": null
}}
""".strip()

    async def _repair_to_schema(self, broken_json_text: str, source_url: str) -> Recipe:
        """
        Second call (no tools) using structured output schema to repair invalid JSON-as-text.
        """
        prompt = f"""
You will be given a JSON-like text that is supposed to match this Recipe schema.
Fix it and output ONLY valid JSON that matches the schema exactly.

Rules:
- Do not add ingredients/steps that are not present in the given text.
- Preserve raw ingredient lines as-is.
- If missing: null for optional scalars, [] for lists.
- Ensure "source" is "{source_url}"
- id/createdAt/updatedAt must be null.

Broken JSON-like text:
<<<
{broken_json_text}
>>>
""".strip()

        response = await self.client.aio.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt,
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_json_schema=self._recipe_schema,
                temperature=0.0,
                max_output_tokens=4096,
            ),
        )

        # Prefer parsed if available
        parsed = getattr(response, "parsed", None)
        if isinstance(parsed, dict):
            data = parsed
        else:
            text = get_response_text(response).strip()
            data = safe_json_loads(text)

        data = self._normalize_recipe_json(data, source_url=source_url)
        return Recipe.model_validate(data)

    def _normalize_recipe_json(self, recipe_json: Dict[str, Any], source_url: str) -> Dict[str, Any]:
        normalized: Dict[str, Any] = dict(recipe_json or {})
        normalized["source"] = source_url

        # Ensure list fields exist
        for k in ("ingredientGroups", "ingredients", "instructionGroups", "instructions", "notes", "images"):
            if normalized.get(k) is None:
                normalized[k] = []

        # servings -> str
        if "servings" in normalized and normalized["servings"] is not None and not isinstance(normalized["servings"], str):
            normalized["servings"] = str(normalized["servings"])

        # id/createdAt/updatedAt for extracted recipes
        normalized.setdefault("id", None)
        normalized.setdefault("createdAt", None)
        normalized.setdefault("updatedAt", None)

        # imageUrl strictness
        img = normalized.get("imageUrl")
        if isinstance(img, str):
            s = img.strip()
            if not s or not s.startswith(("http://", "https://")):
                normalized["imageUrl"] = None

        # images: remove empties
        imgs = normalized.get("images")
        if isinstance(imgs, list):
            normalized["images"] = [x for x in imgs if isinstance(x, str) and x.strip()]

        # tolerate ingredientGroups.ingredients as ["..."] instead of [{"raw": "..."}]
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
