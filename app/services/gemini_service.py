"""Gemini LLM service for recipe extraction and generation."""

import asyncio
import json
import logging
import re
from typing import Any, Dict, List

from google import genai
from google.genai import types

from app.config import settings
from app.models.recipe import Recipe
from app.utils.exceptions import GeminiError

logger = logging.getLogger(__name__)


class GeminiService:
    """Service for interacting with Gemini API."""

    def __init__(self):
        """Initialize Gemini service."""
        self._client = None

    @property
    def client(self):
        """Get or create Gemini client (lazy initialization)."""
        if self._client is None:
            self._client = genai.Client(api_key=settings.gemini_api_key)
        return self._client

    async def extract_recipe_from_image(self, image_data: bytes, mime_type: str) -> Recipe:
        """
        Extract recipe from image using Gemini Vision.

        Args:
            image_data: Image file bytes
            mime_type: MIME type of the image

        Returns:
            Extracted Recipe object

        Raises:
            GeminiError: If extraction fails
        """
        prompt = self._build_image_extraction_prompt()

        try:
            logger.info(f"Extracting recipe from image (mime_type: {mime_type})")

            # Use synchronous API wrapped in executor
            loop = asyncio.get_event_loop()
            
            # Convert image to base64 for the API
            import base64
            image_base64 = base64.b64encode(image_data).decode('utf-8')
            
            response = await loop.run_in_executor(
                None,
                lambda: self.client.models.generate_content(
                    model="gemini-2.5-flash-light",
                    contents=[
                        prompt,
                        {"inline_data": {"mime_type": mime_type, "data": image_base64}}
                    ],
                    config=types.GenerateContentConfig(
                        response_mime_type="text/plain",
                    ),
                )
            )

            if response is None or response.text is None:
                raise GeminiError("Gemini returned empty response for image extraction")

            response_text = response.text.strip()
            logger.debug(f"Gemini image response (first 500 chars): {response_text[:500]}")

            # Parse JSON
            json_text = self._extract_json_from_text(response_text)
            recipe_json = json.loads(json_text)
            normalized = self._normalize_recipe_json(recipe_json)
            
            return Recipe(**normalized)

        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse JSON from image extraction: {str(e)}")
            raise GeminiError(f"Failed to parse recipe JSON from image: {str(e)}") from e
        except Exception as e:
            logger.error(f"Image extraction failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to extract recipe from image: {str(e)}") from e

    async def generate_recipe_from_ingredients(self, ingredients: List[str]) -> Recipe:
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
            logger.info(f"Generating recipe from {len(ingredients)} ingredients")

            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                None,
                lambda: self.client.models.generate_content(
                    model="gemini-2.5-flash-light",
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        response_mime_type="text/plain",
                    ),
                )
            )

            if response is None or response.text is None:
                raise GeminiError("Gemini returned empty response for recipe generation")

            response_text = response.text.strip()
            logger.debug(f"Gemini generation response (first 500 chars): {response_text[:500]}")

            # Parse JSON
            json_text = self._extract_json_from_text(response_text)
            recipe_json = json.loads(json_text)
            normalized = self._normalize_recipe_json(recipe_json)
            
            return Recipe(**normalized)

        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse JSON from recipe generation: {str(e)}")
            raise GeminiError(f"Failed to parse generated recipe JSON: {str(e)}") from e
        except Exception as e:
            logger.error(f"Recipe generation failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to generate recipe: {str(e)}") from e

    async def generate_recipe_from_text(self, user_prompt: str) -> Recipe:
        """
        Generate a recipe from free-form text (chat-based).

        Args:
            user_prompt: User's text describing what they want

        Returns:
            Generated Recipe object

        Raises:
            GeminiError: If generation fails
        """
        prompt = self._build_text_generation_prompt(user_prompt)

        try:
            logger.info(f"Generating recipe from text prompt")

            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                None,
                lambda: self.client.models.generate_content(
                    model="gemini-2.5-flash-light",
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        response_mime_type="text/plain",
                    ),
                )
            )

            if response is None or response.text is None:
                raise GeminiError("Gemini returned empty response for text generation")

            response_text = response.text.strip()
            logger.debug(f"Gemini text generation response (first 500 chars): {response_text[:500]}")

            # Parse JSON
            json_text = self._extract_json_from_text(response_text)
            recipe_json = json.loads(json_text)
            normalized = self._normalize_recipe_json(recipe_json)
            
            return Recipe(**normalized)

        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse JSON from text generation: {str(e)}")
            raise GeminiError(f"Failed to parse generated recipe JSON: {str(e)}") from e
        except Exception as e:
            logger.error(f"Text recipe generation failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to generate recipe from text: {str(e)}") from e

    def _build_image_extraction_prompt(self) -> str:
        """Build prompt for recipe extraction from image."""
        return """
חלץ את המתכון מהתמונה.
החזר אובייקט JSON תקין בלבד בתבנית Recipe.

כללים נוקשים:
- שמור על טקסט מדויק של המרכיבים כפי שמופיע בתמונה. אל תתרגם, אל תנרמל, אל תשנה יחידות/כמויות.
- אל תמציא מרכיבים/שלבים שלא קיימים בתמונה.
- אם מידע לא מופיע: null לשדות אופציונליים, [] לרשימות.

instructionGroups:
- זהה את כל הכותרות שמחלקות את ההוראות.
- לעולם אל תשאיר instructionGroup עם name: null. אם אין כותרת, תמזג את ההוראות לתוך הקבוצה הקודמת.

nutrition (חובה למלא):
- חשב את הערכים התזונתיים על בסיס כל המרכיבים והכמויות במתכון.
- אל תשאיר null בערכים תזונתיים - תמיד מלא מספרים.

החזר JSON בלבד. ללא markdown. ללא code blocks. ללא הסברים.

תבנית:
{
  "title": null,
  "language": null,
  "servings": null,
  "prepTimeMinutes": null,
  "cookTimeMinutes": null,
  "totalTimeMinutes": null,
  "ingredientGroups": [{"name": null, "ingredients": [{"raw": ""}]}],
  "ingredients": [""],
  "instructionGroups": [{"name": "כותרת הסעיף", "instructions": [""]}],
  "instructions": [""],
  "notes": [],
  "images": [],
  "nutrition": {
    "calories": 0,
    "protein_g": 0,
    "fat_g": 0,
    "carbs_g": 0,
    "per": "מנה"
  }
}
""".strip()

    def _build_generation_prompt(self, ingredients: List[str]) -> str:
        """Build prompt for recipe generation from ingredients."""
        ingredients_text = "\n".join(f"- {ing}" for ing in ingredients)
        
        return f"""
צור מתכון מקורי ויצירתי עם המרכיבים הבאים:
{ingredients_text}

החזר אובייקט JSON תקין בלבד בתבנית Recipe.

כללים:
- צור מתכון שמשתמש במרכיבים הנתונים (אפשר להוסיף תבלינים בסיסיים).
- כתוב הוראות ברורות ומפורטות.
- instructionGroups: חלק להכנה, בישול, הגשה לפי הצורך. לעולם אל תשאיר name: null.

nutrition (חובה למלא):
- חשב את הערכים התזונתיים על בסיס כל המרכיבים.
- אל תשאיר null בערכים תזונתיים - תמיד מלא מספרים.

החזר JSON בלבד. ללא markdown. ללא code blocks. ללא הסברים.

תבנית:
{{
  "title": null,
  "language": "he",
  "servings": null,
  "prepTimeMinutes": null,
  "cookTimeMinutes": null,
  "totalTimeMinutes": null,
  "ingredientGroups": [{{"name": null, "ingredients": [{{"raw": ""}}]}}],
  "ingredients": [""],
  "instructionGroups": [{{"name": "הכנה", "instructions": [""]}}],
  "instructions": [""],
  "notes": [],
  "images": [],
  "nutrition": {{
    "calories": 0,
    "protein_g": 0,
    "fat_g": 0,
    "carbs_g": 0,
    "per": "מנה"
  }}
}}
""".strip()

    def _build_text_generation_prompt(self, user_prompt: str) -> str:
        """Build prompt for recipe generation from free-form text."""
        return f"""
המשתמש ביקש:
{user_prompt}

צור מתכון מתאים לבקשה.
החזר אובייקט JSON תקין בלבד בתבנית Recipe.

כללים:
- צור מתכון שמתאים לבקשת המשתמש.
- כתוב הוראות ברורות ומפורטות.
- instructionGroups: חלק להכנה, בישול, הגשה לפי הצורך. לעולם אל תשאיר name: null.

nutrition (חובה למלא):
- חשב את הערכים התזונתיים על בסיס כל המרכיבים.
- אל תשאיר null בערכים תזונתיים - תמיד מלא מספרים.

החזר JSON בלבד. ללא markdown. ללא code blocks. ללא הסברים.

תבנית:
{{
  "title": null,
  "language": "he",
  "servings": null,
  "prepTimeMinutes": null,
  "cookTimeMinutes": null,
  "totalTimeMinutes": null,
  "ingredientGroups": [{{"name": null, "ingredients": [{{"raw": ""}}]}}],
  "ingredients": [""],
  "instructionGroups": [{{"name": "הכנה", "instructions": [""]}}],
  "instructions": [""],
  "notes": [],
  "images": [],
  "nutrition": {{
    "calories": 0,
    "protein_g": 0,
    "fat_g": 0,
    "carbs_g": 0,
    "per": "מנה"
  }}
}}
""".strip()

    def _extract_json_from_text(self, text: str) -> str:
        """Extract JSON object from text."""
        text = text.strip()
        
        # Remove markdown code blocks
        text = re.sub(r"^```json\s*", "", text, flags=re.MULTILINE)
        text = re.sub(r"^```\s*", "", text, flags=re.MULTILINE)
        text = text.strip()
        
        if text.startswith("{") and text.endswith("}"):
            return text
        
        first_brace = text.find("{")
        last_brace = text.rfind("}")
        
        if first_brace != -1 and last_brace != -1 and last_brace > first_brace:
            return text[first_brace:last_brace + 1]
        
        return text

    def _normalize_recipe_json(self, recipe_json: Dict[str, Any]) -> Dict[str, Any]:
        """Normalize recipe JSON to satisfy Pydantic model types."""
        normalized: Dict[str, Any] = dict(recipe_json or {})

        # Ensure list fields exist
        for k in ("ingredientGroups", "ingredients", "instructionGroups", "instructions", "notes", "images"):
            if normalized.get(k) is None:
                normalized[k] = []

        # servings -> str
        if "servings" in normalized and normalized["servings"] is not None and not isinstance(normalized["servings"], str):
            normalized["servings"] = str(normalized["servings"])

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
