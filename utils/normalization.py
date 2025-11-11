# utils/normalization.py
"""Recipe normalization utilities."""

from typing import Any, List
from models import RecipeModel


def safe_strip(v: Any) -> str:
    """Safely strip whitespace from a value."""
    return "" if v is None else str(v).strip()


def ensure_list(value: Any) -> list:
    """Ensure value is a list."""
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return list(value.values())
    return [value] if value else []


def remove_exact_duplicates(seq: List[str]) -> List[str]:
    """Remove exact duplicates while preserving order."""
    seen = set()
    out: List[str] = []
    for item in seq:
        if item and item not in seen:
            seen.add(item)
            out.append(item)
    return out


def parse_time_value(time_str: Any) -> int:
    """Parse time value to integer minutes."""
    if isinstance(time_str, int):
        return time_str
    if isinstance(time_str, str):
        try:
            return int(time_str)
        except ValueError:
            return 0
    return 0


def parse_servings(servings_str: Any) -> int:
    """Parse servings value to integer."""
    if isinstance(servings_str, int):
        return servings_str
    if isinstance(servings_str, str):
        try:
            return int(servings_str)
        except ValueError:
            return 1
    return 1


def normalize_recipe_fields(recipe_data: dict) -> RecipeModel:
    """Normalize a recipe dictionary to RecipeModel."""
    if not recipe_data.get("title") and recipe_data.get("recipeName"):
        recipe_data["title"] = recipe_data["recipeName"]

    prep_time = parse_time_value(recipe_data.get("prepTime", 0))
    cook_time = parse_time_value(recipe_data.get("cookTime", 0))

    if "servings" in recipe_data:
        servings = parse_servings(recipe_data["servings"])
    elif "recipeYield" in recipe_data:
        servings = parse_servings(recipe_data["recipeYield"])
    else:
        servings = 1

    ingredients = ensure_list(recipe_data.get("ingredients", []))
    ingredients = [str(x).strip() for x in ingredients if x]
    ingredients = remove_exact_duplicates(ingredients)

    instructions = recipe_data.get("instructions", [])
    if isinstance(instructions, str):
        instructions = [x.strip() for x in instructions.split("\n") if x.strip()]
    else:
        instructions = [str(x).strip() for x in ensure_list(instructions) if x]
    instructions = remove_exact_duplicates(instructions)

    tags = recipe_data.get("tags", [])
    if isinstance(tags, str):
        tags = [x.strip() for x in tags.split(",") if x.strip()]
    else:
        tags = [str(x).strip() for x in ensure_list(tags) if x]

    return RecipeModel(
        title=safe_strip(recipe_data.get("title", "")),
        description=safe_strip(recipe_data.get("description", "")),
        ingredients=ingredients,
        instructions=instructions,
        prepTime=prep_time,
        cookTime=cook_time,
        servings=servings,
        tags=tags,
        notes=safe_strip(recipe_data.get("notes", "")),
        source=safe_strip(recipe_data.get("source", "")),
        imageUrl=safe_strip(recipe_data.get("imageUrl", "")),
    )

