"""Shared Gemini API helper utilities."""

from functools import lru_cache
from typing import Any, Dict


def clean_schema_for_gemini(schema: Dict[str, Any]) -> Dict[str, Any]:
    """
    Clean Pydantic JSON schema for Gemini responseSchema format.
    - Resolves $ref references to their definitions (Gemini doesn't support $ref)
    - Removes 'additionalProperties' (Gemini rejects this field)
    - Removes Pydantic metadata fields (title, description, examples, $defs)
    - Handles anyOf for Optional fields (extracts the non-null type)
    """
    defs = schema.get("$defs", {})

    def resolve_ref(ref: str) -> Dict[str, Any]:
        """Resolve a $ref to its definition."""
        if ref.startswith("#/$defs/"):
            def_name = ref[len("#/$defs/"):]
            if def_name in defs:
                return defs[def_name]
        return {}

    def clean(s: Dict[str, Any]) -> Dict[str, Any]:
        if not isinstance(s, dict):
            return s

        # If this is a $ref, resolve it first
        if "$ref" in s:
            resolved = resolve_ref(s["$ref"])
            return clean(resolved)

        result: Dict[str, Any] = {}

        for key, value in s.items():
            # Skip fields Gemini doesn't accept or Pydantic metadata
            if key in ("additionalProperties", "additional_properties", "title",
                       "description", "examples", "example", "$defs"):
                continue

            # Recursively clean nested dicts
            if isinstance(value, dict):
                result[key] = clean(value)
            elif isinstance(value, list):
                result[key] = [clean(item) if isinstance(item, dict) else item for item in value]
            else:
                result[key] = value

        # Handle anyOf for Optional fields - extract the non-null type
        if "anyOf" in result:
            any_of = result.pop("anyOf")
            for option in any_of:
                if isinstance(option, dict) and option.get("type") != "null":
                    result.update(option)
                    break

        return result

    return clean(schema)


@lru_cache(maxsize=1)
def get_clean_recipe_schema() -> dict:
    """Return the Recipe model JSON schema cleaned for Gemini, cached."""
    from app.models.recipe import Recipe
    return clean_schema_for_gemini(Recipe.model_json_schema())
