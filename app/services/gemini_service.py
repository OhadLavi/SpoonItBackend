""""Gemini LLM service for recipe extraction and generation (structured JSON)."""

import logging
import re
import json
from typing import Optional, Any, Dict

from google import genai
from google.genai import types
from pydantic import ValidationError

from app.config import settings
from app.models.recipe import Recipe
from app.utils.exceptions import GeminiError

logger = logging.getLogger(__name__)


def _extract_first_json_object(text: str) -> str:
    t = (text or "").strip()
    if not t:
        return t
    t = re.sub(r"^```(?:json)?\s*", "", t, flags=re.MULTILINE)
    t = re.sub(r"\s*```\s*$", "", t, flags=re.MULTILINE).strip()
    if t.startswith("{") and t.endswith("}"):
        return t
    i = t.find("{")
    j = t.rfind("}")
    if i != -1 and j != -1 and j > i:
        return t[i : j + 1].strip()
    return t


def _get_response_text(response: Any) -> str:
    try:
        t = getattr(response, "text", None)
        if isinstance(t, str) and t.strip():
            return t
    except Exception:
        pass
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


class GeminiService:
    """Service for interacting with Gemini API."""

    def __init__(self):
        self._client: Optional[genai.Client] = None
        self._recipe_schema: Dict[str, Any] = Recipe.model_json_schema()

    @property
    def client(self) -> genai.Client:
        """Get or create Gemini client (lazy initialization)."""
        if self._client is None:
            self._client = genai.Client(api_key=settings.gemini_api_key)
        return self._client

    async def extract_recipe_from_text(self, text: str, source_url: Optional[str] = None) -> Recipe:
        prompt = self._build_extraction_prompt(text)

        try:
            logger.info(f"Extracting recipe from text (length: {len(text)} chars)")

            response = await self.client.aio.models.generate_content(
                model="gemini-2.5-flash",
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_json_schema=self._recipe_schema,
                    temperature=0,
                ),
            )

            response_text = _get_response_text(response)
            if not response_text.strip():
                raise GeminiError("Gemini returned empty response (no JSON).")

            recipe_json = json.loads(_extract_first_json_object(response_text))
            recipe_json = self._normalize_recipe_json(recipe_json, source_url=source_url)

            recipe = Recipe.model_validate(recipe_json)

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
                    temperature=0,
                ),
            )

            response_text = _get_response_text(response)
            if not response_text.strip():
                raise GeminiError("Gemini returned empty response (no JSON).")

            recipe_json = json.loads(_extract_first_json_object(response_text))
            recipe_json = self._normalize_recipe_json(recipe_json, source_url=None)

            return Recipe.model_validate(recipe_json)

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
                    temperature=0.7,  # generation can be creative
                ),
            )

            response_text = _get_response_text(response)
            if not response_text.strip():
                raise GeminiError("Gemini returned empty response (no JSON).")

            recipe_json = json.loads(_extract_first_json_object(response_text))
            recipe_json = self._normalize_recipe_json(recipe_json, source_url=None)

            return Recipe.model_validate(recipe_json)

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
                ),
            )

            response_text = _get_response_text(response)
            if not response_text.strip():
                raise GeminiError("Gemini returned empty response (no JSON).")

            recipe_json = json.loads(_extract_first_json_object(response_text))
            recipe_json = self._normalize_recipe_json(recipe_json, source_url=None)

            return Recipe.model_validate(recipe_json)

        except (json.JSONDecodeError, ValidationError) as e:
            logger.error(f"Gemini generate-from-text JSON parse/validation failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Invalid structured JSON from Gemini (generate-from-text): {str(e)}") from e
        except Exception as e:
            logger.error(f"Gemini recipe generation from text failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to generate recipe: {str(e)}") from e

    def _build_extraction_prompt(self, text: str) -> str:
        return f"""Extract recipe information from the following text.

Rules:
- Preserve EXACT ingredient raw text and amounts as written. Do NOT translate or normalize.
- Do NOT invent ingredients or steps.
- If missing info: use null for optional scalars, and [] for lists.
- Fill both ingredientGroups and ingredients (flat list of raw).
- Fill both instructionGroups and instructions (flat list in order).
- Return JSON only (no markdown, no explanations).

Text:
{text}
"""

    def _build_image_extraction_prompt(self) -> str:
        return """Extract recipe information from this image.

Rules:
- Preserve EXACT ingredient raw text and amounts as written. Do NOT translate or normalize.
- Do NOT invent ingredients or steps.
- If missing info: use null for optional scalars, and [] for lists.
- Fill both ingredientGroups and ingredients (flat list of raw).
- Fill both instructionGroups and instructions (flat list in order).
- Return JSON only (no markdown, no explanations).
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

    def _normalize_recipe_json(self, recipe_json: Dict[str, Any], source_url: Optional[str]) -> Dict[str, Any]:
        normalized: Dict[str, Any] = dict(recipe_json or {})

        # set source if provided
        if source_url:
            normalized["source"] = source_url

        # ensure list fields exist
        for k in ("ingredientGroups", "ingredients", "instructionGroups", "instructions", "notes", "images"):
            if normalized.get(k) is None:
                normalized[k] = []

        # servings -> str
        if "servings" in normalized and normalized["servings"] is not None and not isinstance(normalized["servings"], str):
            normalized["servings"] = str(normalized["servings"])

        # imageUrl strictness (HttpUrl)
        img = normalized.get("imageUrl")
        if isinstance(img, str):
            s = img.strip()
            if not s or not s.startswith(("http://", "https://")):
                normalized["imageUrl"] = None

        # images: remove empties
        imgs = normalized.get("images")
        if isinstance(imgs, list):
            normalized["images"] = [x for x in imgs if isinstance(x, str) and x.strip()]

        # tolerant ingredientGroups format
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
