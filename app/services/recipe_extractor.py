"""Unified recipe extraction service with robust fallbacks."""

from __future__ import annotations

import logging
from typing import Optional

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
        Extraction strategy:
          A) Try url_context (1 call, structured JSON)
          B) If fails -> Google Search + TEXT (call 1) -> JSON (call 2)

        This avoids the unsupported combo: Google Search + JSON in the same request.
        """
        # A) url_context
        try:
            logger.info(f"[extract_from_url] Trying url_context for: {url}")
            return await self.scraper_service.extract_recipe_from_url(url)
        except ScrapingError as e:
            logger.warning(f"[extract_from_url] url_context failed, fallback to Google Search. Reason: {e}")

        # B) google_search 2-step
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
