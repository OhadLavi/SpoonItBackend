"""Web scraping service using Gemini with url_context."""

import asyncio
import json
import logging
import re
from typing import Any, Dict

from google import genai
from google.genai import types

from app.config import settings
from app.models.recipe import Recipe
from app.utils.exceptions import ScrapingError

logger = logging.getLogger(__name__)


class ScraperService:
    """Service for scraping recipe content from URLs using Gemini url_context tool."""

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

            # Use synchronous API wrapped in executor (async API doesn't work with url_context)
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                None,
                lambda: self.client.models.generate_content(
                    model="gemini-2.5-flash",
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        tools=[{"url_context": {}}],
                        response_mime_type="text/plain",
                    ),
                )
            )

            logger.info(f"Gemini response received for {url}")

            # Direct text access (works with sync API)
            if not hasattr(response, 'text') or response.text is None:
                raise ScrapingError("Gemini response has no text content")
            
            response_text = response.text.strip()
            
            if not response_text:
                raise ScrapingError("Gemini returned empty response")
            
            logger.debug(f"Gemini response text (first 500 chars): {response_text[:500]}")

            # Parse JSON response - remove markdown code blocks if present
            response_text = re.sub(r"^```json\s*", "", response_text, flags=re.MULTILINE)
            response_text = re.sub(r"^```\s*", "", response_text, flags=re.MULTILINE)
            response_text = response_text.strip()
            
            # Extract JSON from text (handle cases where there's extra text)
            json_text = self._extract_json_from_text(response_text)
            
            recipe_json = json.loads(json_text)
            
            # Normalize recipe JSON
            normalized_recipe_json = self._normalize_recipe_json(recipe_json, source_url=url)
            
            # Log parsed recipe for debugging
            logger.info(f"Parsed recipe: title='{normalized_recipe_json.get('title')}', ingredients count={len(normalized_recipe_json.get('ingredients', []))}")
            
            recipe = Recipe(**normalized_recipe_json)

            # Validate recipe has meaningful content
            if not recipe.title or len(recipe.ingredients) == 0:
                logger.error(f"Extracted recipe is empty or invalid: title='{recipe.title}', ingredients={len(recipe.ingredients)}")
                raise ScrapingError(
                    "Failed to extract meaningful recipe content. The page may not contain a valid recipe."
                )

            return recipe

        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse JSON from Gemini response: {str(e)}")
            logger.debug(f"Response text: {response_text[:1000] if 'response_text' in locals() else 'N/A'}")
            raise ScrapingError(f"Failed to parse recipe JSON: {str(e)}") from e
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

CRITICAL: החזר רק JSON תקין, ללא markdown, ללא code blocks, ללא הסברים."""

    def _extract_json_from_text(self, text: str) -> str:
        """
        Extract JSON object from text, handling cases where there's extra text.
        
        Args:
            text: Text that may contain JSON
            
        Returns:
            Extracted JSON string
        """
        text = text.strip()
        
        # If it already looks like JSON (starts with { and ends with })
        if text.startswith("{") and text.endswith("}"):
            return text
        
        # Find first { and last }
        first_brace = text.find("{")
        last_brace = text.rfind("}")
        
        if first_brace != -1 and last_brace != -1 and last_brace > first_brace:
            return text[first_brace:last_brace + 1]
        
        # If no JSON found, return original (will fail with better error)
        return text

    def _normalize_recipe_json(self, recipe_json: Dict[str, Any], source_url: str) -> Dict[str, Any]:
        """Normalize recipe JSON to satisfy Pydantic model types."""
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
