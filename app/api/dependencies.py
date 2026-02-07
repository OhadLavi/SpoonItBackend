"""Shared API dependencies."""

from functools import lru_cache

from app.services.recipe_extractor import RecipeExtractor


@lru_cache(maxsize=1)
def get_recipe_extractor() -> RecipeExtractor:
    """Get recipe extractor service instance (singleton, reused across requests)."""
    return RecipeExtractor()

