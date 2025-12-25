"""Unified recipe extraction service with robust fallbacks."""

from __future__ import annotations

import logging

from app.models.recipe import Recipe
from app.services.gemini_service import GeminiService
from app.services.image_service import ImageService
from app.services.scraper_service import ScraperService
from app.utils.exceptions import GeminiError, ImageProcessingError, ScrapingError

logger = logging.getLogger(__name__)


class RecipeExtractor:
    """Unified service for extracting recipes from various sources."""

    def __init__(self):
        self.gemini_service = GeminiService()
        self.scraper_service = ScraperService()
        self.image_service = ImageService()

    async def extract_from_url(self, url: str) -> Recipe:
        """
        Strategy:
          1) Try url_context -> TEXT
             then TEXT -> JSON (no tools)
          2) If fails -> Google Search -> TEXT
             then TEXT -> JSON (no tools)

        Rationale:
          Tool use + response_mime_type='application/json' is unsupported (400).
          So all tool calls must be text/plain, and JSON must be produced in a second call without tools.
        """
        # 1) url_context -> text -> json
        try:
            logger.info(f"[extract_from_url] Trying url_context (text) for: {url}")
            text = await self.scraper_service.fetch_recipe_text_via_url_context(url)
            return await self.gemini_service.extract_recipe_from_text(text, source_url=url)
        except ScrapingError as e:
            logger.warning(f"[extract_from_url] url_context failed, fallback to Google Search. Reason: {e}")

        # 2) google_search -> text -> json
        try:
            logger.info(f"[extract_from_url] Trying Google Search 2-step for: {url}")
            return await self.gemini_service.extract_recipe_from_url_via_google_search(url)
        except GeminiError as e:
            logger.error(f"[extract_from_url] Google Search 2-step failed: {e}", exc_info=True)
            raise ScrapingError(f"Failed to extract recipe from URL using fallbacks: {e}") from e

    async def extract_from_image(self, image_data: bytes, filename: str) -> Recipe:
        try:
            validated_data, mime_type = self.image_service.validate_image(image_data, filename)
            return await self.gemini_service.extract_recipe_from_image(validated_data, mime_type)
        except ImageProcessingError:
            raise
        except GeminiError:
            raise
        except Exception as e:
            logger.error(f"Unexpected error extracting recipe from image: {str(e)}", exc_info=True)
            raise ImageProcessingError(f"Failed to extract recipe from image: {str(e)}") from e

    async def generate_from_ingredients(self, ingredients: list[str]) -> Recipe:
        try:
            return await self.gemini_service.generate_recipe_from_ingredients(ingredients)
        except GeminiError:
            raise
        except Exception as e:
            logger.error(f"Unexpected error generating recipe: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to generate recipe: {str(e)}") from e

    async def generate_from_text(self, prompt: str) -> Recipe:
        try:
            return await self.gemini_service.generate_recipe_from_text(prompt)
        except GeminiError:
            raise
        except Exception as e:
            logger.error(f"Unexpected error generating recipe from text: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to generate recipe: {str(e)}") from e
