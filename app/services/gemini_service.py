"""Gemini LLM service for recipe extraction and generation (structured JSON + tool JSON-as-text)."""

from __future__ import annotations

import json
import logging
from typing import Any, Dict, Optional

from google import genai
from google.genai import types
from pydantic import ValidationError

from app.config import settings
from app.models.recipe import Recipe
from app.utils.exceptions import GeminiError
from app.services.gemini_utils import (
    get_response_text,
    has_google_search_tool,
    log_empty_response,
    safe_json_loads,
)

logger = logging.getLogger(__name__)


class GeminiService:
    """Service for interacting with Gemini API."""

    def __init__(self):
        self._client: Optional[genai.Client] = None
        self._recipe_schema: Dict[str, Any] = Recipe.model_json_schema()

    @property
    def client(self) -> genai.Client:
        if self._client is None:
            self._client = genai.Client(api_key=settings.gemini_api_key)
        return self._client

    # -------------------------
    # Tool-based URL extraction (ONE CALL when possible)
    # -------------------------

    async def extract_recipe_from_url_via_google_search(self, url: str) -> Recipe:
        """
        Google Search tool + text/plain + JSON-as-text (parse ourselves).
        If parsing fails, repair using structured output WITHOUT tools.
        """
        tools = [types.Tool(google_search=types.GoogleSearch())]
        prompt = self._build_google_search_json_prompt(url)

        try:
            response = await self.client.aio.models.generate_content(
                model="gemini-2.5-flash",
                contents=prompt,
                config=types.GenerateContentConfig(
                    tools=tools,
                    response_mime_type="text/plain",
                    temperature=0.0,
                    max_output_tokens=4096,
                ),
            )

            text = get_response_text(response).strip()
            if not text:
                log_empty_response("Google Search call returned empty text.", response)
                raise GeminiError("Google Search call returned empty text.")

            try:
                data = safe_json_loads(text)
                data = self._normalize_recipe_json(data, source_url=url)
                recipe = Recipe.model_validate(data)
                if not recipe.title or len(recipe.ingredients) == 0:
                    raise GeminiError("Extracted recipe is empty/invalid (missing title or ingredients).")
                return recipe
            except (json.JSONDecodeError, ValidationError, ValueError) as e:
                logger.warning(f"Google Search JSON-as-text parse failed, attempting repair: {e}", exc_info=True)
                return await self._repair_to_schema(text, source_url=url)

        except GeminiError:
            raise
        except Exception as e:
            logger.error(f"Google Search extraction failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to extract recipe via Google Search: {str(e)}") from e

    # -------------------------
    # Structured JSON methods (NO TOOLS)
    # -------------------------

    async def extract_recipe_from_text(self, text: str, source_url: Optional[str] = None) -> Recipe:
        prompt = self._build_extraction_prompt(text)

        try:
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

            parsed = getattr(response, "parsed", None)
            if isinstance(parsed, dict):
                data = parsed
            else:
                response_text = get_response_text(response).strip()
                if not response_text:
                    raise GeminiError("Gemini returned empty response (no JSON).")
                data = safe_json_loads(response_text)

            data = self._normalize_recipe_json(data, source_url=source_url)
            recipe = Recipe.model_validate(data)

            if not recipe.title or len(recipe.ingredients) == 0:
                raise GeminiError("Failed to extract meaningful recipe content from text.")

            return recipe

        except (json.JSONDecodeError, ValidationError) as e:
            logger.error(f"Gemini JSON parse/validation failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Invalid structured JSON from Gemini: {str(e)}") from e
        except Exception as e:
            logger.error(f"Gemini extraction failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to extract recipe: {str(e)}") from e

    async def extract_recipe_from_image(self, image_data: bytes, mime_type: str) -> Recipe:
        prompt = self._build_image_extraction_prompt()

        try:
            image_part = types.Part.from_bytes(data=image_data, mime_type=mime_type)

            response = await self.client.aio.models.generate_content(
                model="gemini-2.5-flash",
                contents=[prompt, image_part],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_json_schema=self._recipe_schema,
                    temperature=0.0,
                    max_output_tokens=4096,
                ),
            )

            parsed = getattr(response, "parsed", None)
            if isinstance(parsed, dict):
                data = parsed
            else:
                response_text = get_response_text(response).strip()
                if not response_text:
                    raise GeminiError("Gemini returned empty response (no JSON).")
                data = safe_json_loads(response_text)

            data = self._normalize_recipe_json(data, source_url=None)
            return Recipe.model_validate(data)

        except (json.JSONDecodeError, ValidationError) as e:
            logger.error(f"Gemini image JSON parse/validation failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Invalid structured JSON from Gemini (image): {str(e)}") from e
        except Exception as e:
            logger.error(f"Gemini image extraction failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to extract recipe from image: {str(e)}") from e

    async def generate_recipe_from_ingredients(self, ingredients: list[str]) -> Recipe:
        prompt = self._build_generation_prompt(ingredients)

        try:
            response = await self.client.aio.models.generate_content(
                model="gemini-2.5-flash",
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_json_schema=self._recipe_schema,
                    temperature=0.7,
                    max_output_tokens=4096,
                ),
            )

            parsed = getattr(response, "parsed", None)
            if isinstance(parsed, dict):
                data = parsed
            else:
                response_text = get_response_text(response).strip()
                if not response_text:
                    raise GeminiError("Gemini returned empty response (no JSON).")
                data = safe_json_loads(response_text)

            data = self._normalize_recipe_json(data, source_url=None)
            return Recipe.model_validate(data)

        except (json.JSONDecodeError, ValidationError) as e:
            logger.error(f"Gemini generation JSON parse/validation failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Invalid structured JSON from Gemini (generation): {str(e)}") from e
        except Exception as e:
            logger.error(f"Gemini recipe generation failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to generate recipe: {str(e)}") from e

    async def generate_recipe_from_text(self, prompt: str) -> Recipe:
        try:
            response = await self.client.aio.models.generate_content(
                model="gemini-2.5-flash",
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_json_schema=self._recipe_schema,
                    temperature=0.7,
                    max_output_tokens=4096,
                ),
            )

            parsed = getattr(response, "parsed", None)
            if isinstance(parsed, dict):
                data = parsed
            else:
                response_text = get_response_text(response).strip()
                if not response_text:
                    raise GeminiError("Gemini returned empty response (no JSON).")
                data = safe_json_loads(response_text)

            data = self._normalize_recipe_json(data, source_url=None)
            return Recipe.model_validate(data)

        except (json.JSONDecodeError, ValidationError) as e:
            logger.error(f"Gemini generate-from-text JSON parse/validation failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Invalid structured JSON from Gemini (generate-from-text): {str(e)}") from e
        except Exception as e:
            logger.error(f"Gemini recipe generation from text failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to generate recipe: {str(e)}") from e

    # -------------------------
    # Repair (no tools)
    # -------------------------

    async def _repair_to_schema(self, broken_json_text: str, source_url: str) -> Recipe:
        prompt = f"""
You will be given JSON-like text that should match the Recipe schema.
Fix it and output ONLY valid JSON that matches the schema exactly.

Rules:
- Do not invent ingredients/steps. Only fix formatting/escaping/structure.
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

        parsed = getattr(response, "parsed", None)
        if isinstance(parsed, dict):
            data = parsed
        else:
            response_text = get_response_text(response).strip()
            if not response_text:
                raise GeminiError("Repair call returned empty JSON.")
            data = safe_json_loads(response_text)

        data = self._normalize_recipe_json(data, source_url=source_url)
        return Recipe.model_validate(data)

    # -------------------------
    # Prompts
    # -------------------------

    def _build_google_search_json_prompt(self, url: str) -> str:
        return f"""
השתמש ב-Google Search (grounding) כדי לגשת ל-URL הבא ולקרוא את העמוד:
{url}

החזר אובייקט JSON תקין בלבד בתבנית Recipe.

כללים נוקשים:
- שמור על טקסט מדויק של המרכיבים כפי שמופיע בעמוד (ingredientGroups.ingredients[].raw + ingredients[]). אל תתרגם, אל תנרמל, אל תשנה יחידות/כמויות.
- אל תמציא מרכיבים/שלבים שלא קיימים בעמוד.
- אם מידע לא מופיע: null לשדות אופציונליים, [] לרשימות.
- מלא גם ingredientGroups וגם ingredients.
- מלא גם instructionGroups וגם instructions (לפי הסדר).
- notes: כל טיפים/המלצות/הערות שמופיעים בעמוד.
- imageUrl: כתובת מלאה (http/https) אם קיימת, אחרת null. images: רשימת URLים לתמונות אם קיימת, אחרת [].
- id/createdAt/updatedAt: null
- source: שים את ה-URL במחרוזת

החזר JSON בלבד. ללא markdown. ללא code blocks. ללא הסברים.

תבנית:
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

    def _build_extraction_prompt(self, text: str) -> str:
        return f"""Extract recipe information from the following text.

CRITICAL RULES:
- Preserve EXACT ingredient raw text and amounts as written. Do NOT translate or normalize.
- Do NOT invent ingredients or steps.
- If missing info: use null for optional scalars, and [] for lists.
- Fill both ingredientGroups and ingredients (flat list of raw strings).
- Fill both instructionGroups and instructions (flat list in order).
- notes: tips/recommendations/notes if present.
- imageUrl: full http/https URL if present, else null. images: list of URLs or [].
- Return JSON ONLY, no markdown, no explanations.

Text:
{text}
"""

    def _build_image_extraction_prompt(self) -> str:
        return """Extract recipe information from this image.

CRITICAL RULES:
- Preserve EXACT ingredient raw text and amounts as written. Do NOT translate or normalize.
- Do NOT invent ingredients or steps.
- If missing info: use null for optional scalars, and [] for lists.
- Fill both ingredientGroups and ingredients.
- Fill both instructionGroups and instructions in order.
- Return JSON ONLY, no markdown, no explanations.
"""

    def _build_generation_prompt(self, ingredients: list[str]) -> str:
        ingredients_text = "\n".join(f"- {ing}" for ing in ingredients)
        return f"""Generate a creative recipe using the following ingredients.

Rules:
- Return JSON only (no markdown, no explanations).
- Use the provided schema fields.
- ingredients must be a flat list including amounts.
- instructionGroups and instructions must be ordered.

Available ingredients:
{ingredients_text}
"""

    # -------------------------
    # Normalization
    # -------------------------

    def _normalize_recipe_json(self, recipe_json: Dict[str, Any], source_url: Optional[str]) -> Dict[str, Any]:
        normalized: Dict[str, Any] = dict(recipe_json or {})

        if source_url:
            normalized["source"] = source_url

        for k in ("ingredientGroups", "ingredients", "instructionGroups", "instructions", "notes", "images"):
            if normalized.get(k) is None:
                normalized[k] = []

        if "servings" in normalized and normalized["servings"] is not None and not isinstance(normalized["servings"], str):
            normalized["servings"] = str(normalized["servings"])

        normalized.setdefault("id", None)
        normalized.setdefault("createdAt", None)
        normalized.setdefault("updatedAt", None)

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
