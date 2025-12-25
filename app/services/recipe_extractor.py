"""Unified recipe extraction service."""

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
        """Initialize recipe extractor with dependencies."""
        self.gemini_service = GeminiService()
        self.scraper_service = ScraperService()
        self.image_service = ImageService()

    async def extract_from_url(self, url: str) -> Recipe:
        """
        Extract recipe from URL.

        Args:
            url: Recipe URL

        Returns:
            Extracted Recipe object

        Raises:
            ScrapingError: If scraping fails
        """
        try:
            # Extract recipe directly using Gemini with url_context
            recipe = await self.scraper_service.extract_recipe_from_url(url)

            return recipe

        except ScrapingError:
            raise
        except Exception as e:
            logger.error(f"Unexpected error extracting recipe from URL: {str(e)}", exc_info=True)
            raise ScrapingError(f"Failed to extract recipe: {str(e)}") from e

    async def extract_from_image(self, image_data: bytes, filename: str) -> Recipe:
        """
        Extract recipe from image.

        Args:
            image_data: Image file bytes
            filename: Original filename

        Returns:
            Extracted Recipe object

        Raises:
            ImageProcessingError: If image processing fails
            GeminiError: If extraction fails
        """
        try:
            # Validate image
            validated_data, mime_type = self.image_service.validate_image(image_data, filename)

            # Extract recipe using Gemini Vision
            recipe = await self.gemini_service.extract_recipe_from_image(validated_data, mime_type)

            return recipe

        except ImageProcessingError:
            raise
        except GeminiError:
            raise
        except Exception as e:
            logger.error(f"Unexpected error extracting recipe from image: {str(e)}", exc_info=True)
            raise ImageProcessingError(f"Failed to extract recipe: {str(e)}") from e

    async def generate_from_ingredients(self, ingredients: list[str]) -> Recipe:
        """
        Generate recipe from ingredients list.

        Args:
            ingredients: List of ingredient strings

        Returns:
            Generated Recipe object

        Raises:
            GeminiError: If generation fails
        """
        try:
            recipe = await self.gemini_service.generate_recipe_from_ingredients(ingredients)
            return recipe

        except GeminiError:
            raise
        except Exception as e:
            logger.error(f"Unexpected error generating recipe: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to generate recipe: {str(e)}") from e

    async def generate_from_text(self, prompt: str) -> Recipe:
        """
        Generate recipe from free-form text prompt.
        
        This method is designed for chat-based interactions where the prompt
        is already fully formed.

        Args:
            prompt: Complete prompt text for recipe generation

        Returns:
            Generated Recipe object

        Raises:
            GeminiError: If generation fails
        """
        try:
            recipe = await self.gemini_service.generate_recipe_from_text(prompt)
            return recipe

        except GeminiError:
            raise
        except Exception as e:
            logger.error(f"Unexpected error generating recipe from text: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to generate recipe: {str(e)}") from e

