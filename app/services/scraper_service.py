"""Web scraping service using Gemini with url_context."""

import logging
from typing import Optional

from google import genai
from google.genai import types

from app.config import settings
from app.models.recipe import Recipe
from app.utils.exceptions import ScrapingError

logger = logging.getLogger(__name__)


class ScraperService:
    """Service for scraping recipe content from URLs using Gemini."""

    def __init__(self):
        """Initialize scraper service."""
        self._client = None

    @property
    def client(self):
        """Get or create Gemini client (lazy initialization)."""
        if self._client is None:
            self._client = genai.Client(api_key=settings.gemini_api_key)
        return self._client

    async def extract_recipe_from_url(self, url: str) -> Recipe:
        """
        Extract recipe directly from URL using Gemini with url_context.

        Args:
            url: Recipe URL to extract

        Returns:
            Extracted Recipe object

        Raises:
            ScrapingError: If extraction fails
        """
        prompt = self._build_url_extraction_prompt(url)

        try:
            logger.info(f"Extracting recipe from URL: {url}")

            # Run in executor to avoid blocking
            import asyncio
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                None,
                lambda: self.client.models.generate_content(
                    model="gemini-2.5-flash",
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        tools=[{"url_context": {}}],
                        response_mime_type="application/json",
                    ),
                )
            )

            logger.info(f"Gemini response received for {url}")
            logger.debug(f"Gemini response text: {response.text[:500]}")  # First 500 chars

            # Parse JSON response
            import json
            recipe_json = json.loads(response.text)
            
            # Normalize recipe JSON
            normalized_recipe_json = self._normalize_recipe_json(recipe_json)
            
            # Log parsed recipe for debugging
            logger.info(f"Parsed recipe: title='{normalized_recipe_json.get('title')}', ingredients count={len(normalized_recipe_json.get('ingredients', []))}")
            
            recipe = Recipe(**normalized_recipe_json)

            # Set source URL
            recipe.source = url
            
            # Validate recipe has meaningful content
            if not recipe.title or len(recipe.ingredients) == 0:
                logger.error(f"Extracted recipe is empty or invalid: title='{recipe.title}', ingredients={len(recipe.ingredients)}")
                raise ScrapingError(
                    "Failed to extract meaningful recipe content. The page may not contain a valid recipe."
                )

            return recipe

        except Exception as e:
            logger.error(f"Recipe extraction from URL failed: {str(e)}", exc_info=True)
            raise ScrapingError(f"Failed to extract recipe from URL: {str(e)}") from e

    def _build_url_extraction_prompt(self, url: str) -> str:
        """Build prompt for recipe extraction from URL."""
        return f"""השתמש ב-URL עצמו: {url}

חלץ את המתכון *בדיוק כפי שמופיע בעמוד*.

כללים נוקשים:
- אל תנרמל ואל תשנה כמויות/מידות.
- אל תוסיף מרכיבים שלא כתובים בעמוד.
- שמור על הטקסט המדויק של כל מרכיב והוראה.
- אם משהו לא מופיע בעמוד, השתמש ב-null.
- חלץ גם הערות אם יש (הערות, טיפים, המלצות וכו').
- אם יש קבוצות של הוראות (כמו "הכנת הבצק", "הגשה", "הכנת המילוי" וכו'), חלץ אותן ל-instructionGroups.

החזר JSON בפורמט הבא בדיוק:

{{
  "title": "שם המתכון",
  "description": "תיאור המתכון או null",
  "language": "קוד שפה (לדוגמה 'he', 'en') או null",
  "servings": "מספר מנות או null",
  "prepTimeMinutes": מספר או null,
  "cookTimeMinutes": מספר או null,
  "totalTimeMinutes": מספר או null,
  "ingredientGroups": [
    {{
      "name": "שם הקבוצה או null",
      "ingredients": [
        {{"raw": "טקסט המרכיב בדיוק כפי שמופיע"}}
      ]
    }}
  ],
  "ingredients": ["רשימה שטוחה של כל המרכיבים"],
  "instructionGroups": [
    {{
      "name": "שם קבוצת ההוראות (כמו 'הכנת הבצק', 'הגשה') או null",
      "instructions": ["שלב 1", "שלב 2"]
    }}
  ],
  "instructions": ["רשימה שטוחה של כל ההוראות לפי סדר"],
  "notes": ["הערה 1", "הערה 2"] או [],
  "imageUrl": "URL של התמונה הראשית או null",
  "images": ["URL תמונה 1", "URL תמונה 2"] או [],
  "nutrition": {{
    "calories": מספר או null,
    "protein_g": מספר או null,
    "fat_g": מספר או null,
    "carbs_g": מספר או null,
    "per": "ל-מה" או null
  }}
}}

CRITICAL: החזר רקJSON תקין, ללא markdown, ללא code blocks, ללא הסברים."""

    def _normalize_recipe_json(self, recipe_json: dict) -> dict:
        """Normalize recipe JSON to satisfy Pydantic model types."""
        normalized = dict(recipe_json)

        # Normalize servings to string
        servings = normalized.get("servings")
        if servings is not None and not isinstance(servings, str):
            normalized["servings"] = str(servings)

        return normalized
