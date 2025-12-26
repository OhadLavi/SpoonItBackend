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
    """Service for extracting recipes from URLs using Gemini url_context tool."""

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
        Falls back to Google Search if url_context fails.

        Args:
            url: Recipe URL to extract

        Returns:
            Extracted Recipe object

        Raises:
            ScrapingError: If extraction fails
        """
        prompt = self._build_url_extraction_prompt(url)

        # Try url_context first
        try:
            logger.info(f"Extracting recipe from URL using url_context: {url}")
            return await self._extract_with_url_context(url, prompt)
        except Exception as url_error:
            logger.warning(f"url_context extraction failed: {str(url_error)}, falling back to Google Search")
            # Fallback to Google Search
            try:
                logger.info(f"Trying Google Search for URL: {url}")
                return await self._extract_with_google_search(url, prompt)
            except Exception as search_error:
                logger.error(f"Both url_context and Google Search failed. url_context error: {str(url_error)}, Google Search error: {str(search_error)}")
                raise ScrapingError(f"Failed to extract recipe from URL: url_context failed ({str(url_error)}), Google Search failed ({str(search_error)})") from search_error

    async def _extract_with_url_context(self, url: str, prompt: str) -> Recipe:
        """Extract recipe using url_context tool."""
        # Use synchronous API wrapped in executor (async API doesn't work with url_context)
        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None,
            lambda: self.client.models.generate_content(
                model="gemini-2.5-flash-lite",
                contents=prompt,
                config=types.GenerateContentConfig(
                    tools=[{"url_context": {}}],
                    response_mime_type="text/plain",
                ),
            )
        )

        logger.info(f"Gemini url_context response received for {url}")

        # Check response
        if response is None or response.text is None:
            raise ScrapingError("Gemini url_context returned empty response")
        
        response_text = response.text.strip()
        
        if not response_text:
            raise ScrapingError("Gemini url_context returned empty response")
        
        logger.info(f"Gemini url_context full response text:\n{response_text}")

        return self._parse_and_validate_response(response_text, url)

    async def _extract_with_google_search(self, url: str, prompt: str) -> Recipe:
        """Extract recipe using Google Search tool as fallback."""
        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None,
            lambda: self.client.models.generate_content(
                model="gemini-2.5-flash-lite",
                contents=prompt,
                config=types.GenerateContentConfig(
                    tools=[types.Tool(google_search=types.GoogleSearch())],
                    response_mime_type="text/plain",
                ),
            )
        )

        logger.info(f"Gemini Google Search response received for {url}")

        # Check response
        if response is None or response.text is None:
            raise ScrapingError("Gemini Google Search returned empty response")
        
        response_text = response.text.strip()
        
        if not response_text:
            raise ScrapingError("Gemini Google Search returned empty response")
        
        logger.info(f"Gemini Google Search full response text:\n{response_text}")

        return self._parse_and_validate_response(response_text, url)

    def _parse_and_validate_response(self, response_text: str, url: str) -> Recipe:
        """Parse and validate Gemini response into Recipe object."""
        # Parse JSON response - remove markdown code blocks if present
        response_text = re.sub(r"^```json\s*", "", response_text, flags=re.MULTILINE)
        response_text = re.sub(r"^```\s*", "", response_text, flags=re.MULTILINE)
        response_text = response_text.strip()
        
        # Extract JSON from text
        json_text = self._extract_json_from_text(response_text)
        
        recipe_json = json.loads(json_text)
        
        # Normalize recipe JSON
        normalized_recipe_json = self._normalize_recipe_json(recipe_json)
        
        # Count total ingredients from groups
        total_ingredients = sum(len(group.get('ingredients', [])) for group in normalized_recipe_json.get('ingredientGroups', []))
        logger.info(f"Parsed recipe: title='{normalized_recipe_json.get('title')}', ingredientGroups count={len(normalized_recipe_json.get('ingredientGroups', []))}, total ingredients={total_ingredients}, instructionGroups count={len(normalized_recipe_json.get('instructionGroups', []))}")
        
        recipe = Recipe(**normalized_recipe_json)

        # Validate recipe has meaningful content - check ingredientGroups
        if not recipe.title or total_ingredients == 0:
            raise ScrapingError("Failed to extract meaningful recipe content. The page may not contain a valid recipe.")

        return recipe

    def _build_url_extraction_prompt(self, url: str) -> str:
        """Build prompt for recipe extraction from URL."""
        return f"""
השתמש ב-URL עצמו: {url}

חלץ את המתכון *בדיוק כפי שמופיע בעמוד*.
החזר אובייקט JSON תקין בלבד בתבנית Recipe.

כללים נוקשים:
- שמור על טקסט מדויק של המרכיבים כפי שמופיע בעמוד. אל תתרגם, אל תנרמל, אל תשנה יחידות/כמויות.
- אל תמציא מרכיבים/שלבים שלא קיימים בעמוד.
- אם מידע לא מופיע: null לשדות אופציונליים, [] לרשימות.
- notes: כל טיפים/המלצות/הערות שמופיעים בעמוד.
- images: מערך של תמונות של המתכון בפורמט png, jpg בלבד. כתובת מלאה (http/https) אם קיימות, אחרת [].

חשוב מאוד - instructionGroups (חובה):
- זהה בקפידה את כל הכותרות/כותרות משנה בעמוד שמחלקות את ההוראות (כמו "הכנת הבצק", "הכנת המילוי", "בישול", "הגשה" וכו').
- כל כותרת שמופיעה לפני קבוצת הוראות חייבת להופיע בשדה "name" של ה-instructionGroup המתאים.
- אם יש הוראות ללא כותרת מפורשת, אבל הן שייכות לכותרת הקודמת (למשל הוראות המשך של "הכנת הבצק"), אז תמזג אותן לתוך ה-instructionGroup הקודם עם הכותרת - אל תיצור instructionGroup חדש עם name: null.
- כלל חשוב: לעולם אל תשאיר instructionGroup עם name: null. אם אין כותרת, תמזג את ההוראות לתוך הקבוצה הקודמת.
- דוגמה: אם יש "הכנת הבצק" ואחר כך הוראות נוספות ללא כותרת שקשורות לבצק, הכל צריך להיות ב-instructionGroup אחד עם name: "הכנת הבצק".

חשוב מאוד - nutrition (חובה למלא):
- אתה חייב לחשב את הערכים התזונתיים. זה לא אופציונלי - אתה חייב למלא את כל השדות.
- חשב את הערכים התזונתיים על בסיס כל המרכיבים והכמויות במתכון:
  * סכום את הקלוריות מכל המרכיבים
  * סכום את החלבון (גרם) מכל המרכיבים
  * סכום את השומן (גרם) מכל המרכיבים
  * סכום את הפחמימות (גרם) מכל המרכיבים
- שדה "per" צריך להכיל את היחידה - בדרך כלל "מנה" או "מנה אחת" (לפי servings), או "100 גרם" אם רלוונטי.
- אם יש ערכים תזונתיים מפורשים בעמוד, השתמש בהם. אם לא, חשב אותם בעצמך - זה חובה.
- אל תשאיר null בערכים תזונתיים - תמיד מלא מספרים.

החזר JSON בלבד. ללא markdown. ללא code blocks. ללא הסברים.

תבנית:
{{
  "title": null,
  "language": null,
  "servings": null,
  "prepTimeMinutes": null,
  "cookTimeMinutes": null,
  "totalTimeMinutes": null,
  "ingredientGroups": [{{"name": null, "ingredients": [{{"raw": ""}}]}}],
  "instructionGroups": [{{"name": "כותרת הסעיף או null אם אין", "instructions": [""]}}],
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

זכור: nutrition חייב להיות עם ערכים מספריים (לא null). חשב אותם על בסיס המרכיבים.
""".strip()

    def _extract_json_from_text(self, text: str) -> str:
        """Extract JSON object from text."""
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

        # Ensure list fields exist (only groups, no flat lists)
        for k in ("ingredientGroups", "instructionGroups", "notes", "images"):
            if normalized.get(k) is None:
                normalized[k] = []
        
        # Ensure flat ingredients list is empty (not used in new schema, but model requires it for backward compatibility)
        normalized.setdefault("ingredients", [])

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
