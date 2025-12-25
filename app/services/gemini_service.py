"""Gemini LLM service for recipe extraction and generation (structured JSON + guarded tool usage)."""

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
from app.services.gemini_utils import get_response_text, safe_json_loads

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

    def _build_config(
        self,
        *,
        tools: Optional[list[Any]] = None,
        response_json_schema: Optional[Dict[str, Any]] = None,
        response_mime_type: Optional[str] = None,
        temperature: float = 0.0,
        max_output_tokens: Optional[int] = None,
    ) -> types.GenerateContentConfig:
        """
        IMPORTANT: Tool use with response_mime_type='application/json' is unsupported.
        Therefore:
          - If tools are provided -> must be text/plain and MUST NOT include response_json_schema.
          - If no tools and response_json_schema is provided -> force application/json.
        """
        if tools:
            if response_json_schema is not None:
                raise GeminiError(
                    "Unsupported config: cannot use tools together with response_json_schema. "
                    "Use 2-step pipeline: (1) tool->text, (2) json without tools."
                )
            if response_mime_type and response_mime_type.lower() == "application/json":
                raise GeminiError(
                    "Unsupported config: tool use with response_mime_type='application/json' is unsupported. "
                    "Use text/plain for tool call, then a second JSON call without tools."
                )
            response_mime_type = response_mime_type or "text/plain"
        else:
            if response_json_schema is not None:
                response_mime_type = "application/json"

        return types.GenerateContentConfig(
            tools=tools,
            response_mime_type=response_mime_type,
            response_json_schema=response_json_schema,
            temperature=temperature,
            max_output_tokens=max_output_tokens,
        )

    # -------------------------
    # Google Search 2-step (text -> JSON)
    # -------------------------

    async def fetch_recipe_text_via_google_search(self, url: str) -> str:
        prompt = f"""
Use Google Search to access and read this URL:
{url}

TASK:
Extract ONLY the recipe content exactly as it appears on the page.

STRICT RULES:
- Preserve ingredient lines and measurements EXACTLY as written.
- Do NOT normalize, translate, or convert units.
- Do NOT invent missing ingredients/steps.

Output MUST be plain text, organized as:

TITLE:
<one line>

DESCRIPTION:
<one paragraph or empty>

INGREDIENTS:
- <line 1 exactly>
- <line 2 exactly>
...

INSTRUCTIONS:
1. <step 1 exactly>
2. <step 2 exactly>
...

NOTES:
- <note 1 exactly>
- <note 2 exactly>

IMAGES:
- <image url 1 if present>
- <image url 2 if present>

If a section does not exist, output it but leave it empty.
Return plain text ONLY (no JSON, no markdown).
""".strip()

        tools = [types.Tool(google_search=types.GoogleSearch())]

        try:
            response = await self.client.aio.models.generate_content(
                model="gemini-2.5-flash",
                contents=prompt,
                config=self._build_config(
                    tools=tools,
                    response_mime_type="text/plain",
                    temperature=0.0,
                    max_output_tokens=3072,
                ),
            )

            text = get_response_text(response).strip()
            if not text:
                raise GeminiError("Google Search call returned empty text.")

            # Optional: debug snippet (keep it short)
            logger.debug(f"[google_search text snippet] {text[:600]}")
            return text

        except Exception as e:
            logger.error(f"Google Search fetch failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to fetch recipe text via Google Search: {str(e)}") from e

    async def extract_recipe_from_url_via_google_search(self, url: str) -> Recipe:
        recipe_text = await self.fetch_recipe_text_via_google_search(url)
        return await self.extract_recipe_from_text(recipe_text, source_url=url)

    # -------------------------
    # Structured JSON methods (NO TOOLS)
    # -------------------------

    async def extract_recipe_from_text(self, text: str, source_url: Optional[str] = None) -> Recipe:
        prompt = self._build_extraction_prompt(text)

        try:
            data = await self._generate_recipe_json_with_repair(prompt)
            data = self._normalize_recipe_json(data, source_url=source_url)

            recipe = Recipe.model_validate(data)
            if not recipe.title or len(recipe.ingredients) == 0:
                raise GeminiError("Failed to extract meaningful recipe content from text.")
            return recipe

        except GeminiError:
            raise
        except Exception as e:
            logger.error(f"Gemini extraction failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to extract recipe: {str(e)}") from e

    async def extract_recipe_from_image(self, image_data: bytes, mime_type: str) -> Recipe:
        prompt = self._build_image_extraction_prompt()

        try:
            image_part = types.Part.from_bytes(data=image_data, mime_type=mime_type)
            data = await self._generate_recipe_json_with_repair([prompt, image_part])

            data = self._normalize_recipe_json(data, source_url=None)
            return Recipe.model_validate(data)

        except GeminiError:
            raise
        except Exception as e:
            logger.error(f"Gemini image extraction failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to extract recipe from image: {str(e)}") from e

    async def generate_recipe_from_ingredients(self, ingredients: list[str]) -> Recipe:
        prompt = self._build_generation_prompt(ingredients)

        try:
            data = await self._generate_recipe_json_with_repair(prompt, temperature=0.7)
            data = self._normalize_recipe_json(data, source_url=None)
            return Recipe.model_validate(data)

        except GeminiError:
            raise
        except Exception as e:
            logger.error(f"Gemini recipe generation failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to generate recipe: {str(e)}") from e

    async def generate_recipe_from_text(self, prompt: str) -> Recipe:
        try:
            data = await self._generate_recipe_json_with_repair(prompt, temperature=0.7)
            data = self._normalize_recipe_json(data, source_url=None)
            return Recipe.model_validate(data)

        except GeminiError:
            raise
        except Exception as e:
            logger.error(f"Gemini recipe generation from text failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to generate recipe from text: {str(e)}") from e

    # -------------------------
    # Core JSON generation with repair
    # -------------------------

    async def _generate_recipe_json_with_repair(
        self,
        contents: Any,
        temperature: float = 0.0,
    ) -> Dict[str, Any]:
        """
        1) Try structured JSON with schema
        2) If JSON is invalid -> call repair (schema-enforced) and return repaired JSON
        """
        # First try
        response = await self.client.aio.models.generate_content(
            model="gemini-2.5-flash",
            contents=contents,
            config=self._build_config(
                tools=None,
                response_json_schema=self._recipe_schema,
                temperature=temperature,
                max_output_tokens=8192,
            ),
        )

        raw = get_response_text(response)
        if not raw.strip():
            raise GeminiError("Gemini returned empty response (no JSON).")

        try:
            data = safe_json_loads(raw)
            return data
        except json.JSONDecodeError as e:
            logger.warning(f"Structured JSON came back invalid, attempting repair. Reason: {e}")
            logger.debug(f"[bad json snippet] {raw[:900]}")
            return await self._repair_recipe_json(raw)

    async def _repair_recipe_json(self, bad_text: str) -> Dict[str, Any]:
        """
        Ask Gemini to output a valid JSON object matching the Recipe schema.
        This is an extra call ONLY on failure.
        """
        # Avoid huge prompts
        clipped = bad_text.strip()
        if len(clipped) > 20000:
            clipped = clipped[:20000]

        repair_prompt = f"""
You are a strict JSON repair function.

Given the following BROKEN JSON (it may be missing commas, have trailing text, code fences, etc.),
output a VALID JSON object that matches the provided Recipe schema.

RULES:
- Output JSON ONLY. No markdown. No explanations.
- Keep ingredient raw strings EXACTLY as they appear in the broken JSON/text. Do not translate or normalize.
- If a field is missing, set it to null or [] according to the schema defaults/intent.

BROKEN JSON:
{clipped}
""".strip()

        try:
            response = await self.client.aio.models.generate_content(
                model="gemini-2.5-flash",
                contents=repair_prompt,
                config=self._build_config(
                    tools=None,
                    response_json_schema=self._recipe_schema,
                    temperature=0.0,
                    max_output_tokens=8192,
                ),
            )

            fixed_raw = get_response_text(response)
            if not fixed_raw.strip():
                raise GeminiError("Repair call returned empty JSON.")

            data = safe_json_loads(fixed_raw)
            return data

        except (json.JSONDecodeError, ValidationError) as e:
            logger.error(f"Repair JSON parse/validation failed: {str(e)}", exc_info=True)
            raise GeminiError(f"JSON repair failed: {str(e)}") from e
        except Exception as e:
            logger.error(f"Repair call failed: {str(e)}", exc_info=True)
            raise GeminiError(f"JSON repair call failed: {str(e)}") from e

    # -------------------------
    # Prompts
    # -------------------------

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
