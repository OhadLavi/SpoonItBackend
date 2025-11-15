# utils/normalization.py
"""Recipe normalization utilities.

Goal: convert raw dicts from Gemini into RecipeModel **without** changing the
actual ingredient or instruction text (beyond trimming whitespace).
"""

from __future__ import annotations

from typing import Any, List, Optional

from models import IngredientGroup, RecipeModel


def _as_str(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def _as_str_list(value: Any) -> List[str]:
    """Convert many possible inputs into a list of strings, preserving text."""
    if value is None:
        return []
    if isinstance(value, list):
        out = []
        for v in value:
            s = str(v).strip()
            if s:
                out.append(s)
        return out
    if isinstance(value, str):
        # split only on newlines; keep bullets / numbering as-is
        lines = [line.strip() for line in value.splitlines()]
        return [ln for ln in lines if ln]
    return [str(value).strip()]


def _parse_int(value: Any, default: int) -> int:
    try:
        if isinstance(value, bool):
            return default
        return int(value)
    except (TypeError, ValueError):
        return default


def _normalize_ingredient_groups(raw: Any) -> Optional[List[IngredientGroup]]:
    if not raw:
        return None

    groups: List[IngredientGroup] = []

    if isinstance(raw, dict):
        for category, ings in raw.items():
            cat = _as_str(category)
            ing_list = _as_str_list(ings)
            if cat or ing_list:
                groups.append(IngredientGroup(category=cat, ingredients=ing_list))
    elif isinstance(raw, list):
        for item in raw:
            if isinstance(item, IngredientGroup):
                groups.append(item)
            elif isinstance(item, dict):
                cat = _as_str(item.get("category", ""))
                ing_list = _as_str_list(item.get("ingredients", []))
                if cat or ing_list:
                    groups.append(IngredientGroup(category=cat, ingredients=ing_list))

    return groups or None


def normalize_recipe_fields(recipe_data: dict) -> RecipeModel:
    """Normalize a raw recipe dictionary into RecipeModel."""

    title = _as_str(recipe_data.get("title") or recipe_data.get("recipeName"))
    description = _as_str(recipe_data.get("description"))

    ingredients = _as_str_list(recipe_data.get("ingredients", []))
    instructions = _as_str_list(recipe_data.get("instructions", []))

    prep_time = _parse_int(recipe_data.get("prepTime", 0), 0)
    cook_time = _parse_int(recipe_data.get("cookTime", 0), 0)

    if "servings" in recipe_data:
        servings = _parse_int(recipe_data.get("servings"), 1)
    elif "recipeYield" in recipe_data:
        servings = _parse_int(recipe_data.get("recipeYield"), 1)
    else:
        servings = 1

    tags_raw = recipe_data.get("tags", [])
    tags = _as_str_list(tags_raw)

    notes = _as_str(recipe_data.get("notes"))
    source = _as_str(recipe_data.get("source"))
    image_url = _as_str(recipe_data.get("imageUrl"))

    images_val = recipe_data.get("images")
    images: Optional[List[str]]
    if isinstance(images_val, list):
        images = [str(u).strip() for u in images_val if str(u).strip()]
    elif isinstance(images_val, str) and images_val.strip():
        images = [images_val.strip()]
    else:
        images = None

    ingredients_groups = _normalize_ingredient_groups(
        recipe_data.get("ingredientsGroups")
    )

    return RecipeModel(
        title=title,
        description=description,
        ingredients=ingredients,
        ingredientsGroups=ingredients_groups,
        instructions=instructions,
        prepTime=prep_time,
        cookTime=prep_time if cook_time is None else cook_time,
        servings=servings,
        tags=tags,
        notes=notes,
        source=source,
        imageUrl=image_url,
        images=images,
    )
