"""Shared API dependencies."""

from app.services.recipe_extractor import RecipeExtractor


def get_recipe_extractor() -> RecipeExtractor:
    """Get recipe extractor service instance."""
    return RecipeExtractor()

