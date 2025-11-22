"""Gemini LLM service for recipe extraction and generation."""

import asyncio
import logging
from typing import Optional

import google.generativeai as genai
from google.generativeai.types import HarmCategory, HarmBlockThreshold

from app.config import settings
from app.models.recipe import Recipe
from app.utils.exceptions import GeminiError

logger = logging.getLogger(__name__)


class GeminiService:
    """Service for interacting with Gemini API."""

    def __init__(self):
        """Initialize Gemini service."""
        self._model = None
        self._configured = False

    def _ensure_configured(self):
        """Lazy initialization of Gemini API."""
        if not self._configured:
            genai.configure(api_key=settings.gemini_api_key)
            self._configured = True

    @property
    def model(self):
        """Get or create the Gemini model (lazy initialization)."""
        if self._model is None:
            self._ensure_configured()
            self._model = genai.GenerativeModel(
                model_name=settings.gemini_model,
                safety_settings={
                    HarmCategory.HARM_CATEGORY_HATE_SPEECH: HarmBlockThreshold.BLOCK_NONE,
                    HarmCategory.HARM_CATEGORY_HARASSMENT: HarmBlockThreshold.BLOCK_NONE,
                    HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: HarmBlockThreshold.BLOCK_NONE,
                    HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: HarmBlockThreshold.BLOCK_NONE,
                },
            )
        return self._model

    async def extract_recipe_from_text(
        self, text: str, source_url: Optional[str] = None
    ) -> Recipe:
        """
        Extract recipe from text content using Gemini.

        Args:
            text: Text content containing recipe
            source_url: Optional source URL

        Returns:
            Extracted Recipe object

        Raises:
            GeminiError: If extraction fails
        """
        prompt = self._build_extraction_prompt(text, source_url)

        try:
            # Run in executor to avoid blocking
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                None, lambda: self.model.generate_content(prompt)
            )

            recipe_json = self._parse_response_to_json(response.text)
            normalized_recipe_json = self._normalize_recipe_json(recipe_json)
            recipe = Recipe(**normalized_recipe_json)

            # Set source if provided
            if source_url:
                recipe.source = source_url

            return recipe

        except Exception as e:
            logger.error(f"Gemini extraction failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to extract recipe: {str(e)}") from e

    async def extract_recipe_from_image(self, image_data: bytes, image_mime_type: str) -> Recipe:
        """
        Extract recipe from image using Gemini Vision.

        Args:
            image_data: Image file bytes
            image_mime_type: MIME type of image (e.g., 'image/jpeg')

        Returns:
            Extracted Recipe object

        Raises:
            GeminiError: If extraction fails
        """
        prompt = self._build_image_extraction_prompt()

        try:
            # Create image part
            import PIL.Image
            import io

            image = PIL.Image.open(io.BytesIO(image_data))

            # Run in executor to avoid blocking
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                None, lambda: self.model.generate_content([prompt, image])
            )

            recipe_json = self._parse_response_to_json(response.text)
            normalized_recipe_json = self._normalize_recipe_json(recipe_json)
            recipe = Recipe(**normalized_recipe_json)

            return recipe

        except Exception as e:
            logger.error(f"Gemini image extraction failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to extract recipe from image: {str(e)}") from e

    async def generate_recipe_from_ingredients(self, ingredients: list[str]) -> Recipe:
        """
        Generate a recipe from a list of ingredients.

        Args:
            ingredients: List of ingredient strings

        Returns:
            Generated Recipe object

        Raises:
            GeminiError: If generation fails
        """
        prompt = self._build_generation_prompt(ingredients)

        try:
            # Run in executor to avoid blocking
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                None, lambda: self.model.generate_content(prompt)
            )

            recipe_json = self._parse_response_to_json(response.text)
            normalized_recipe_json = self._normalize_recipe_json(recipe_json)
            recipe = Recipe(**normalized_recipe_json)
            
            return recipe

        except Exception as e:
            logger.error(f"Gemini recipe generation failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to generate recipe: {str(e)}") from e

    def _build_extraction_prompt(self, text: str, source_url: Optional[str] = None) -> str:
        """Build prompt for recipe extraction from text."""
        return f"""Extract the recipe information from the following text and return it as a JSON object matching this exact structure:

{{
  "title": "Recipe title",
  "description": "Recipe description or null",
  "language": "Language code (e.g., 'he', 'en') or null",
  "servings": "Number of servings or null",
  "prepTimeMinutes": number or null,
  "cookTimeMinutes": number or null,
  "totalTimeMinutes": number or null,
  "ingredientGroups": [
    {{
      "name": "Group name or null",
      "ingredients": [
        {{"raw": "exact ingredient text as it appears"}}
      ]
    }}
  ],
  "ingredients": ["flat list of all ingredient raw texts"],
  "instructions": ["step 1", "step 2", ...],
  "notes": ["note 1", "note 2", ...] or [],
  "imageUrl": "main image URL or null",
  "images": ["image URL 1", ...] or [],
  "nutrition": {{
    "calories": number or null,
    "protein_g": number or null,
    "fat_g": number or null,
    "carbs_g": number or null,
    "per": "per what" or null
  }}
}}

CRITICAL RULES:
1. Preserve EXACT ingredient text, amounts, and product names from the original. Do NOT translate, convert, or modify them.
2. You can group ingredients into groups, but keep the raw text exactly as written.
3. Extract all ingredients into both ingredientGroups (grouped) and ingredients (flat list).
4. Return ONLY valid JSON, no markdown, no code blocks, no explanations.
5. If information is missing, use null.

Source URL: {source_url or "Not provided"}

Text to extract from:
{text}
"""

    def _build_image_extraction_prompt(self) -> str:
        """Build prompt for recipe extraction from image."""
        return """Extract the recipe information from this image and return it as a JSON object matching this exact structure:

{
  "title": "Recipe title",
  "description": "Recipe description or null",
  "language": "Language code (e.g., 'he', 'en') or null",
  "servings": "Number of servings or null",
  "prepTimeMinutes": number or null,
  "cookTimeMinutes": number or null,
  "totalTimeMinutes": number or null,
  "ingredientGroups": [
    {
      "name": "Group name or null",
      "ingredients": [
        {"raw": "exact ingredient text as it appears"}
      ]
    }
  ],
  "ingredients": ["flat list of all ingredient raw texts"],
  "instructions": ["step 1", "step 2", ...],
  "notes": ["note 1", "note 2", ...] or [],
  "imageUrl": null,
  "images": [],
  "nutrition": {
    "calories": number or null,
    "protein_g": number or null,
    "fat_g": number or null,
    "carbs_g": number or null,
    "per": "per what" or null
  }
}

CRITICAL RULES:
1. Preserve EXACT ingredient text, amounts, and product names from the image. Do NOT translate, convert, or modify them.
2. You can group ingredients into groups, but keep the raw text exactly as written.
3. Extract all ingredients into both ingredientGroups (grouped) and ingredients (flat list).
4. Return ONLY valid JSON, no markdown, no code blocks, no explanations.
5. If information is missing, use null.
"""

    def _build_generation_prompt(self, ingredients: list[str]) -> str:
        """Build prompt for recipe generation from ingredients."""
        ingredients_text = "\n".join(f"- {ing}" for ing in ingredients)

        return f"""Generate a creative recipe using the following ingredients. Return it as a JSON object matching this exact structure:

{{
  "title": "Recipe title",
  "description": "Brief recipe description",
  "language": "en",
  "servings": "Number of servings",
  "prepTimeMinutes": number or null,
  "cookTimeMinutes": number or null,
  "totalTimeMinutes": number or null,
  "ingredientGroups": [
    {{
      "name": "Group name or null",
      "ingredients": [
        {{"raw": "ingredient with amount"}}
      ]
    }}
  ],
  "ingredients": ["flat list of all ingredients with amounts"],
  "instructions": ["detailed step 1", "detailed step 2", ...],
  "notes": ["helpful tip 1", ...] or [],
  "imageUrl": null,
  "images": [],
  "nutrition": {{
    "calories": number or null,
    "protein_g": number or null,
    "fat_g": number or null,
    "carbs_g": number or null,
    "per": "serving" or null
  }}
}}

Available ingredients:
{ingredients_text}

Return ONLY valid JSON, no markdown, no code blocks, no explanations.
"""

    def _parse_response_to_json(self, response_text: str) -> dict:
        """Parse Gemini response text to JSON dict."""
        import json
        import re

        # Remove markdown code blocks if present
        text = response_text.strip()
        text = re.sub(r"^```json\s*", "", text, flags=re.MULTILINE)
        text = re.sub(r"^```\s*", "", text, flags=re.MULTILINE)
        text = text.strip()

        try:
            return json.loads(text)
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse Gemini response as JSON: {text[:500]}")
            raise GeminiError(f"Invalid JSON response from Gemini: {str(e)}") from e

    def _normalize_recipe_json(self, recipe_json: dict) -> dict:
        """Normalize Gemini recipe JSON to satisfy Pydantic model types."""

        normalized = dict(recipe_json)

        servings = normalized.get("servings")
        if servings is not None and not isinstance(servings, str):
            normalized["servings"] = str(servings)

        return normalized

