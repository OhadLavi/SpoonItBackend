"""Unified recipe data normalization used by both scraper and gemini services."""

import logging
import re
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

# Hebrew unit tokens for ingredient repair
_UNIT_TOKENS = {
    "כפות", "כף", "כפית", "כפיות", "כוס", "כוסות", "מיכל", "קמצוץ",
}
_QTY_UNIT_NAME = re.compile(r"^\s*(\d+(?:[\.,]\d+)?)\s+([^\s]+)\s+(.+?)\s*$")
_UNIT_NAME = re.compile(r"^\s*([^\s]+)\s+(.+?)\s*$")


def normalize_recipe_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Normalize recipe data from Gemini / JSON-LD to match the Recipe model.

    Handles:
    - Wrapped responses (e.g. ``{"Recipe": {...}}``)
    - Alternate time keys (``prepTime`` -> ``prepTimeMinutes``, etc.)
    - Servings normalization (int/str/dict -> Servings object)
    - Flat ``ingredients`` list -> ``ingredientGroups``
    - ``ingredientGroups`` structured normalization
    - Hebrew unit repair via ``_repair_ingredient_units``
    - Nutrition normalization (variant keys, filter to allowed fields)
    - ``instructionGroups`` wrong-format handling
    - Multi-line ingredient / instruction splitting
    - URL-only instruction removal
    - Image URL filtering
    - Total time computation from prep + cook
    """
    # Unwrap wrapped responses (e.g. {"Recipe": {...}})
    if len(data) == 1 and isinstance(list(data.values())[0], dict):
        key = list(data.keys())[0].lower()
        inner = list(data.values())[0]
        if "recipe" in key or "instructiongroups" in inner or "ingredients" in inner:
            logger.info(f"Unwrapping nested JSON response from key: {list(data.keys())[0]}")
            data = inner

    normalized: Dict[str, Any] = dict(data)

    # --- Time key aliases (camelCase / snake_case variants) ---
    if "prepTime" in normalized and "prepTimeMinutes" not in normalized and "prep_time_minutes" not in normalized:
        normalized["prepTimeMinutes"] = normalized.pop("prepTime") or None
    if "cookTime" in normalized and "cookTimeMinutes" not in normalized and "cook_time_minutes" not in normalized:
        normalized["cookTimeMinutes"] = normalized.pop("cookTime") or None
    if "totalTime" in normalized and "totalTimeMinutes" not in normalized and "total_time_minutes" not in normalized:
        normalized["totalTimeMinutes"] = normalized.pop("totalTime") or None

    # --- Servings ---
    _normalize_servings(normalized)

    # --- Flat ingredients -> ingredientGroups ---
    _convert_flat_ingredients(normalized)

    # --- ingredientGroups normalization ---
    _normalize_ingredient_groups(normalized)

    # --- Repair Hebrew unit / name swaps ---
    normalized["ingredientGroups"] = _repair_ingredient_units(normalized.get("ingredientGroups", []))

    # --- Nutrition ---
    _normalize_nutrition(normalized)

    # --- Remove computed / extra fields ---
    normalized.pop("ingredients", None)
    normalized.pop("description", None)
    if "source_url" in normalized:
        normalized["source"] = normalized.pop("source_url")

    # --- Ensure required list fields ---
    normalized.setdefault("ingredientGroups", [])
    normalized.setdefault("notes", [])
    normalized.setdefault("images", [])

    # --- instructionGroups ---
    _normalize_instruction_groups(normalized)

    # --- Multi-line ingredient splitting ---
    _split_multiline_ingredients(normalized)

    # --- Remove URL-only instructions ---
    _remove_url_instructions(normalized)

    # --- Image filtering ---
    _filter_images(normalized)

    # --- Compute total time ---
    _compute_total_time(normalized)

    return normalized


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _normalize_servings(normalized: Dict[str, Any]) -> None:
    if "servings" not in normalized:
        return
    servings = normalized["servings"]
    if isinstance(servings, dict):
        if "amount" not in servings and "unit" not in servings and "raw" not in servings:
            if isinstance(servings.get("value"), (int, float, str)):
                normalized["servings"] = {
                    "amount": str(servings.get("value")),
                    "unit": servings.get("unit"),
                    "raw": servings.get("raw") or str(servings.get("value", ""))
                }
    elif isinstance(servings, (int, float)):
        normalized["servings"] = {"amount": str(int(servings)), "unit": None, "raw": str(int(servings))}
    elif isinstance(servings, str):
        normalized["servings"] = {"amount": None, "unit": None, "raw": servings}
    elif servings is None:
        normalized["servings"] = None
    else:
        normalized["servings"] = None


def _convert_flat_ingredients(normalized: Dict[str, Any]) -> None:
    ingredients = normalized.get("ingredients")
    if not isinstance(ingredients, list) or len(ingredients) == 0:
        return
    if normalized.get("ingredientGroups"):
        return
    logger.info("Converting flat 'ingredients' list to 'ingredientGroups'")
    converted = []
    for ing in ingredients:
        if isinstance(ing, str):
            converted.append({"name": ing, "amount": None, "preparation": None, "raw": ing})
        elif isinstance(ing, dict):
            raw = ing.get("raw", "")
            name = ing.get("name", "")
            amount = ing.get("amount")
            if amount is None:
                qty = ing.get("quantity")
                unit = ing.get("unit")
                if qty or unit:
                    parts = [str(qty)] if qty else []
                    if unit:
                        parts.append(str(unit))
                    amount = " ".join(parts) if parts else None
            converted.append({
                "name": name or raw or str(ing),
                "amount": amount,
                "preparation": ing.get("preparation"),
                "raw": raw or name or str(ing),
            })
        else:
            converted.append({"name": str(ing), "amount": None, "preparation": None, "raw": str(ing)})
    normalized["ingredientGroups"] = [{"name": None, "ingredients": converted}]
    logger.info(f"Created ingredientGroups with {len(converted)} ingredients")


def _normalize_ingredient_groups(normalized: Dict[str, Any]) -> None:
    groups = normalized.get("ingredientGroups")
    if not isinstance(groups, list):
        normalized["ingredientGroups"] = []
        return
    for group in groups:
        if not isinstance(group, dict) or "ingredients" not in group:
            continue
        ings = group["ingredients"]
        if not isinstance(ings, list):
            continue
        result = []
        for ing in ings:
            if isinstance(ing, str):
                result.append({"name": ing, "raw": ing})
            elif isinstance(ing, dict):
                if "name" in ing:
                    amount = ing.get("amount")
                    if amount is None:
                        qty = ing.get("quantity")
                        unit = ing.get("unit")
                        if qty or unit:
                            parts = [str(qty)] if qty else []
                            if unit:
                                parts.append(str(unit))
                            amount = " ".join(parts) if parts else None
                    result.append({
                        "name": ing.get("name", ""),
                        "amount": amount,
                        "preparation": ing.get("preparation"),
                        "raw": ing.get("raw"),
                    })
                elif "item" in ing:
                    result.append({
                        "name": ing.get("item", ""),
                        "amount": ing.get("amount"),
                        "preparation": ing.get("preparation") or ing.get("notes"),
                        "raw": ing.get("raw") or ing.get("item", ""),
                    })
                elif "raw" in ing:
                    result.append(ing)
                else:
                    result.append({"raw": str(ing)})
            else:
                result.append({"raw": str(ing)})
        group["ingredients"] = result


def _normalize_nutrition(normalized: Dict[str, Any]) -> None:
    nutrition = normalized.get("nutrition")
    if not isinstance(nutrition, dict):
        normalized.setdefault("nutrition", None)
        return

    def _f(x: Any) -> Optional[float]:
        if x is None:
            return None
        if isinstance(x, str):
            try:
                cleaned = "".join(c for c in x if c.isdigit() or c == ".")
                return float(cleaned) if cleaned else None
            except (ValueError, TypeError):
                return None
        try:
            val = float(x)
            return val if val >= 0 else None
        except (ValueError, TypeError):
            return None

    result: Dict[str, Any] = {
        "calories": _f(nutrition.get("calories")),
        "protein_g": _f(nutrition.get("protein_g") or nutrition.get("protein")),
        "fat_g": _f(nutrition.get("fat_g") or nutrition.get("fat")),
        "carbs_g": _f(nutrition.get("carbs_g") or nutrition.get("carbs") or nutrition.get("carbohydrates")),
        "per": nutrition.get("per") if isinstance(nutrition.get("per"), str) else "מנה",
    }

    if all(v is None for k, v in result.items() if k != "per"):
        normalized["nutrition"] = None
    else:
        normalized["nutrition"] = result


def _normalize_instruction_groups(normalized: Dict[str, Any]) -> None:
    if "instructionGroups" not in normalized:
        normalized["instructionGroups"] = []
        return
    groups = normalized["instructionGroups"]
    if not isinstance(groups, list):
        normalized["instructionGroups"] = []
        return

    result: List[Dict[str, Any]] = []
    for group in groups:
        if not isinstance(group, dict):
            continue
        if "instruction" in group and "step" in group:
            text = group.get("instruction")
            if text:
                if not result:
                    result.append({"name": "הוראות הכנה", "instructions": []})
                result[0]["instructions"].append(str(text))
        elif "instructions" in group:
            instructions = group.get("instructions", [])
            if not isinstance(instructions, list):
                instructions = [instructions] if instructions else []
            result.append({
                "name": group.get("name") or group.get("groupName"),
                "instructions": [str(inst) for inst in instructions if inst],
            })
        elif "instruction" in group:
            text = group.get("instruction")
            if text:
                if not result:
                    result.append({"name": "הוראות הכנה", "instructions": []})
                result[0]["instructions"].append(str(text))

    if result:
        normalized["instructionGroups"] = result
    elif not normalized["instructionGroups"]:
        normalized["instructionGroups"] = [{"name": "הוראות הכנה", "instructions": []}]
    else:
        for group in normalized["instructionGroups"]:
            if isinstance(group, dict):
                if "instructions" not in group or not isinstance(group["instructions"], list):
                    group["instructions"] = []
                if not group.get("name"):
                    group["name"] = "הוראות הכנה"
                allowed = {"name", "instructions"}
                for key in list(group.keys()):
                    if key not in allowed:
                        group.pop(key)


def _split_multiline_ingredients(normalized: Dict[str, Any]) -> None:
    try:
        for group in normalized.get("ingredientGroups") or []:
            if not isinstance(group, dict):
                continue
            ings = group.get("ingredients") or []
            new_ings: List[Dict[str, Any]] = []
            for ing in ings:
                if not isinstance(ing, dict):
                    continue
                raw = ing.get("raw")
                if raw and isinstance(raw, str) and "\n" in raw:
                    for line in [x.strip() for x in raw.split("\n") if x and x.strip()]:
                        new_ings.append({"amount": None, "name": line, "preparation": None, "raw": line})
                else:
                    new_ings.append(ing)
            group["ingredients"] = new_ings
    except Exception:
        pass


def _remove_url_instructions(normalized: Dict[str, Any]) -> None:
    try:
        for group in normalized.get("instructionGroups") or []:
            if not isinstance(group, dict):
                continue
            inst = group.get("instructions") or []
            if not isinstance(inst, list):
                continue
            cleaned = []
            for s in inst:
                if not isinstance(s, str):
                    continue
                ss = s.strip()
                if not ss:
                    continue
                if re.match(r"^(https?:)?//\S+$", ss) or re.match(r"^https?://\S+$", ss, re.I):
                    continue
                cleaned.append(ss)
            group["instructions"] = cleaned
    except Exception:
        pass


def _filter_images(normalized: Dict[str, Any]) -> None:
    images = normalized.get("images")
    if not images:
        return
    image_extensions = (".jpg", ".jpeg", ".png", ".gif", ".webp", ".avif")
    valid: List[str] = []
    for img_url in images:
        if not isinstance(img_url, str) or not img_url.strip():
            continue
        url_lower = img_url.lower()
        base_url = url_lower.split("?")[0]
        if any(base_url.endswith(ext) for ext in image_extensions):
            valid.append(img_url.strip())
        elif any(ext in url_lower for ext in image_extensions):
            valid.append(img_url.strip())
    if len(valid) != len(images):
        logger.info(f"Filtered images: kept {len(valid)} valid image URLs")
    normalized["images"] = valid


def _compute_total_time(normalized: Dict[str, Any]) -> None:
    total = normalized.get("totalTimeMinutes") or normalized.get("total_time_minutes")
    if total is not None:
        return
    prep = normalized.get("prepTimeMinutes") or normalized.get("prep_time_minutes") or 0
    cook = normalized.get("cookTimeMinutes") or normalized.get("cook_time_minutes") or 0
    if isinstance(prep, (int, float)) and isinstance(cook, (int, float)) and (prep or cook):
        normalized["totalTimeMinutes"] = int(prep + cook)


def _repair_ingredient_units(ingredient_groups: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Repair common Hebrew parsing mistakes where name is actually a unit token."""
    for group in ingredient_groups or []:
        ingredients = group.get("ingredients") or []
        if not isinstance(ingredients, list):
            continue
        for ing in ingredients:
            if not isinstance(ing, dict):
                continue
            raw = (ing.get("raw") or "").strip()
            if not raw:
                continue
            name = (ing.get("name") or "").strip()
            amount = ing.get("amount")
            if name not in _UNIT_TOKENS:
                continue
            m = _QTY_UNIT_NAME.match(raw)
            if m:
                qty, unit, rest = m.group(1), m.group(2), m.group(3)
                if unit in _UNIT_TOKENS and rest:
                    ing["amount"] = f"{qty} {unit}".strip()
                    ing["name"] = rest.strip()
                    continue
            m = _UNIT_NAME.match(raw)
            if m:
                unit, rest = m.group(1), m.group(2)
                if unit in _UNIT_TOKENS and rest and (amount is None or str(amount).strip() in {"", "1"}):
                    ing["amount"] = unit
                    ing["name"] = rest.strip()
    return ingredient_groups
