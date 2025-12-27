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
        
        # Try to extract image URLs from response metadata if available
        image_urls_from_metadata = []
        try:
            if hasattr(response, 'candidates') and response.candidates:
                candidate = response.candidates[0]
                if hasattr(candidate, 'url_context_metadata') and candidate.url_context_metadata:
                    metadata = candidate.url_context_metadata
                    logger.info(f"URL context metadata: {metadata}")
                    # Note: url_context_metadata might contain image info, but structure varies
        except Exception as e:
            logger.debug(f"Could not extract image URLs from metadata: {str(e)}")

        return self._parse_and_validate_response(response_text, url, image_urls_from_metadata)

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

        return self._parse_and_validate_response(response_text, url, [])

    def _parse_and_validate_response(self, response_text: str, url: str, additional_images: list = None) -> Recipe:
        """Parse and validate Gemini response into Recipe object."""
        # Parse JSON response - remove markdown code blocks if present
        response_text = re.sub(r"^```json\s*", "", response_text, flags=re.MULTILINE)
        response_text = re.sub(r"^```\s*", "", response_text, flags=re.MULTILINE)
        response_text = response_text.strip()
        
        # Extract JSON from text
        json_text = self._extract_json_from_text(response_text)
        
        recipe_json = json.loads(json_text)
        
        # Log raw data before normalization (debug level)
        logger.debug(f"Raw data from Gemini: images={recipe_json.get('images')}, prepTimeMinutes={recipe_json.get('prepTimeMinutes')}, cookTimeMinutes={recipe_json.get('cookTimeMinutes')}")
        
        # Normalize recipe JSON
        normalized_recipe_json = self._normalize_recipe_json(recipe_json, source_url=url)
        
        # If no images were extracted but we have additional images from metadata, add them
        if additional_images and len(normalized_recipe_json.get('images', [])) == 0:
            normalized_recipe_json['images'] = additional_images
            logger.info(f"Added {len(additional_images)} images from metadata")
        
        # Count total ingredients from groups
        total_ingredients = sum(len(group.get('ingredients', [])) for group in normalized_recipe_json.get('ingredientGroups', []))
        images_count = len(normalized_recipe_json.get('images', []))
        prep_time = normalized_recipe_json.get('prepTimeMinutes')
        cook_time = normalized_recipe_json.get('cookTimeMinutes')
        logger.info(f"Parsed recipe: title='{normalized_recipe_json.get('title')}', ingredientGroups count={len(normalized_recipe_json.get('ingredientGroups', []))}, total ingredients={total_ingredients}, instructionGroups count={len(normalized_recipe_json.get('instructionGroups', []))}, images count={images_count}, prepTimeMinutes={prep_time}, cookTimeMinutes={cook_time}")
        if images_count == 0:
            logger.debug(f"No images extracted")
        
        recipe = Recipe(**normalized_recipe_json)

        # Validate recipe has meaningful content - check ingredientGroups
        if not recipe.title or total_ingredients == 0:
            raise ScrapingError("Failed to extract meaningful recipe content. The page may not contain a valid recipe.")

        return recipe

    def _build_url_extraction_prompt(self, url: str) -> str:
        """Build prompt for recipe extraction from URL."""
        return f"""חלץ מתכון מ-{url}

**חשוב מאוד: העתק טקסט מילה במילה מהעמוד. אל תשכתב, אל תשנה, אל תוסיף מידע.**

מרכיבים:
- העתק **כל** מרכיב בדיוק כמו שכתוב בעמוד
- אל תדלג על אף מרכיב
- שמור כמויות ויחידות בדיוק כמו שכתובות

הוראות:
- העתק **כל** הוראה בדיוק כמו שכתובה
- אל תכתוב מחדש, אל תפרט, אל תסביר
- שמור כותרות בדיוק כמו שמופיעות: "הכנת המילוי", "הכנת הבצק", "הגשה" וכו'
- אם אין כותרות - שים הכל תחת "הוראות הכנה"

זמנים:
- prepTimeMinutes/cookTimeMinutes: בדקות. null אם לא כתוב
- שעה=60, חצי שעה=30

הערות:
- רק הערות שכתובות בעמוד
- אל תוסיף הסברים משלך

nutrition: חשב ערכים תזונתיים. מספרים בלבד.

החזר JSON בלבד:
{{
  "title": "",
  "language": "he",
  "servings": null,
  "prepTimeMinutes": null,
  "cookTimeMinutes": null,
  "totalTimeMinutes": null,
  "ingredientGroups": [{{"name": null, "ingredients": [{{"raw": ""}}]}}],
  "instructionGroups": [{{"name": "", "instructions": [""]}}],
  "notes": [],
  "images": [],
  "nutrition": {{"calories": 0, "protein_g": 0, "fat_g": 0, "carbs_g": 0, "per": "מנה"}}
}}""".strip()

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

    def _normalize_recipe_json(self, recipe_json: Dict[str, Any], source_url: str = None) -> Dict[str, Any]:
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

        # Normalize time fields to integers or null
        for time_field in ("prepTimeMinutes", "cookTimeMinutes", "totalTimeMinutes"):
            if time_field in normalized:
                time_value = normalized[time_field]
                if time_value is None:
                    continue
                elif isinstance(time_value, (int, float)):
                    # Convert to int, round if float
                    normalized[time_field] = int(round(time_value))
                elif isinstance(time_value, str):
                    # Try to parse string to int
                    try:
                        # Remove any non-numeric characters except digits and decimal point
                        cleaned = ''.join(c for c in time_value if c.isdigit() or c == '.')
                        if cleaned:
                            normalized[time_field] = int(round(float(cleaned)))
                        else:
                            normalized[time_field] = None
                    except (ValueError, TypeError):
                        normalized[time_field] = None
                else:
                    normalized[time_field] = None
        
        # Calculate totalTimeMinutes if not provided but prep and cook times are
        if normalized.get("totalTimeMinutes") is None:
            prep = normalized.get("prepTimeMinutes")
            cook = normalized.get("cookTimeMinutes")
            if prep is not None and cook is not None:
                normalized["totalTimeMinutes"] = prep + cook
            elif prep is not None:
                normalized["totalTimeMinutes"] = prep
            elif cook is not None:
                normalized["totalTimeMinutes"] = cook

        # images: remove empties and validate URLs
        imgs = normalized.get("images")
        if imgs is None:
            normalized["images"] = []
        elif isinstance(imgs, list):
            # Filter out empty strings and ensure all are valid URLs
            valid_images = []
            for img in imgs:
                if isinstance(img, str) and img.strip():
                    img_url = img.strip()
                    # Ensure it's a valid URL (starts with http:// or https://)
                    if img_url.startswith(('http://', 'https://')):
                        valid_images.append(img_url)
                    elif img_url.startswith('//'):
                        # Handle protocol-relative URLs
                        valid_images.append(f'https:{img_url}')
                    elif img_url.startswith('/'):
                        # Handle relative URLs - construct absolute URL from source URL
                        if source_url:
                            try:
                                from urllib.parse import urljoin, urlparse
                                base_url = f"{urlparse(source_url).scheme}://{urlparse(source_url).netloc}"
                                absolute_url = urljoin(base_url, img_url)
                                valid_images.append(absolute_url)
                            except Exception:
                                pass  # Skip failed URL conversions
            normalized["images"] = valid_images
        else:
            normalized["images"] = []

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

        # Handle instruction groups - merge only truly unnamed groups
        instr_groups = normalized.get("instructionGroups")
        if isinstance(instr_groups, list) and instr_groups:
            merged_groups = []
            pending_unnamed_instructions = []
            
            for group in instr_groups:
                if not isinstance(group, dict):
                    continue
                group_name = group.get("name")
                instructions = group.get("instructions", [])
                if not isinstance(instructions, list):
                    instructions = []
                
                # Check if group has a meaningful name
                has_name = group_name and isinstance(group_name, str) and group_name.strip()
                
                if has_name:
                    # If we have pending unnamed instructions, prepend them to this group
                    if pending_unnamed_instructions:
                        instructions = pending_unnamed_instructions + instructions
                        pending_unnamed_instructions = []
                    merged_groups.append({
                        "name": group_name.strip(),
                        "instructions": instructions
                    })
                else:
                    # Collect unnamed instructions
                    pending_unnamed_instructions.extend(instructions)
            
            # Handle any remaining unnamed instructions
            if pending_unnamed_instructions:
                if merged_groups:
                    # Append to the last named group
                    merged_groups[-1]["instructions"].extend(pending_unnamed_instructions)
                else:
                    # No named groups at all, create one with default name
                    merged_groups.append({
                        "name": "הוראות הכנה",
                        "instructions": pending_unnamed_instructions
                    })
            
            # Ensure we have at least one group
            if not merged_groups:
                merged_groups.append({"name": "הוראות הכנה", "instructions": []})
            
            normalized["instructionGroups"] = merged_groups
        
        # Clean up notes - remove AI-generated explanatory notes
        notes = normalized.get("notes")
        if isinstance(notes, list):
            cleaned_notes = []
            skip_patterns = [
                "המתכון המקורי צוין",
                "נעשה שימוש",
                "זמני הכנה ובישול לא צוינו",
                "לא נמצא בטקסט",
                "לא מופיע בעמוד",
            ]
            for note in notes:
                if isinstance(note, str) and note.strip():
                    # Skip AI-generated explanatory notes
                    skip = False
                    for pattern in skip_patterns:
                        if pattern in note:
                            skip = True
                            break
                    if not skip:
                        cleaned_notes.append(note.strip())
            normalized["notes"] = cleaned_notes

        return normalized
