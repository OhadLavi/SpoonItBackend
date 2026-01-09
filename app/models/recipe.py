"""Recipe Pydantic models (Gemini-friendly; ingredients + servings are structured)."""

from __future__ import annotations

from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field, computed_field


def to_camel(s: str) -> str:
    parts = s.split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


class APIModel(BaseModel):
    """
    Base model config:
    - Use snake_case in Python, expose camelCase in JSON (via aliases)
    - Allow populating by either snake_case or camelCase
    - Forbid unknown keys (catches drift early)
    - Strip whitespace from strings
    """

    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
        extra="forbid",
        str_strip_whitespace=True,
    )


class Ingredient(APIModel):
    """
    Ingredient split into amount + name.

    amount: Everything measurement-like (numbers, units, ranges, sizes, 'to taste').
    name: Ingredient label only (no numbers/units).
    """

    amount: Optional[str] = Field(
        default=None,
        description=(
            "Quantity/measurement text ONLY. Include numbers, units, ranges, package sizes, and qualifiers "
            "(e.g., '1 כוס', '250 מ״ל', '2–3 כפות', 'לפי הטעם', 'חבילה (200 גרם)'). "
            "Do NOT include the ingredient name here."
        ),
        examples=["1 כוס", "250 מ״ל", "2–3 כפות", "לפי הטעם", "חבילה (200 גרם)", "30"],
    )
    name: str = Field(
        ...,
        description=(
            "Ingredient name ONLY (e.g., 'קפה חזק', 'שמנת להקצפה', 'אבקת סוכר'). "
            "Do NOT include numbers/units here."
        ),
        examples=["קפה חזק", "שמנת להקצפה", "אבקת סוכר", "בישקוטים"],
    )
    preparation: Optional[str] = Field(
        default=None,
        description="Preparation notes only (e.g., 'קצוץ', 'בטמפ׳ חדר', 'מומס').",
        examples=["קצוץ", "בטמפ׳ חדר", "מומס"],
    )
    raw: Optional[str] = Field(
        default=None,
        description="Original raw ingredient text for reference/traceability.",
        examples=["1 כוס קפה חזק", "שמנת להקצפה 250 מ״ל", "5 כפות אבקת סוכר"],
    )


class IngredientGroup(APIModel):
    """Group of ingredients (e.g., 'לבסיס', 'לקרם')."""

    name: Optional[str] = Field(default=None, description="Group name (e.g., 'לבסיס', 'לקרם').")
    ingredients: List[Ingredient] = Field(default_factory=list, description="List of ingredients in this group")


class InstructionGroup(APIModel):
    """Group of instructions (e.g., 'הכנה', 'הגשה')."""

    name: Optional[str] = Field(default=None, description="Group name (e.g., 'הכנה', 'הגשה').")
    instructions: List[str] = Field(default_factory=list, description="List of instructions in this group")


class Nutrition(APIModel):
    """Nutritional information."""

    calories: Optional[float] = Field(default=None, ge=0, description="Calories per serving")
    protein_g: Optional[float] = Field(default=None, ge=0, description="Protein in grams")
    fat_g: Optional[float] = Field(default=None, ge=0, description="Fat in grams")
    carbs_g: Optional[float] = Field(default=None, ge=0, description="Carbohydrates in grams")
    per: Optional[str] = Field(default=None, description="Per what (e.g., 'slice', 'serving')")


class Servings(APIModel):
    """
    Structured servings/yield.

    amount: keep as string to support '1/2', '2-3', 'אחת', etc.
    unit: what that amount refers to ('מנות', 'רולדה', 'עוגה', etc.)
    raw: original extracted text if available
    """

    amount: Optional[str] = Field(
        default=None,
        description="How many (prefer numeric text if possible; supports ranges/fractions).",
        examples=["1", "4", "2-3", "1/2", "אחת"],
    )
    unit: Optional[str] = Field(
        default=None,
        description="What the amount refers to (e.g., 'מנות', 'רולדה', 'עוגה').",
        examples=["רולדה", "מנות", "עוגה"],
    )
    raw: Optional[str] = Field(
        default=None,
        description="Original servings string from the source (if extracted).",
        examples=["רולדה אחת", "4 מנות"],
    )


class Recipe(APIModel):
    """Unified recipe model returned by all endpoints."""

    id: Optional[str] = Field(default=None, description="Recipe ID (null for extracted recipes)")
    title: Optional[str] = Field(default=None, description="Recipe title")
    source: Optional[str] = Field(default=None, description="Source URL or identifier")

    language: Optional[str] = Field(default=None, description="Language code (e.g., 'he', 'en')")
    servings: Optional[Servings] = Field(default=None, description="Structured servings/yield")

    prep_time_minutes: Optional[int] = Field(default=None, ge=0, description="Preparation time in minutes")
    cook_time_minutes: Optional[int] = Field(default=None, ge=0, description="Cooking time in minutes")
    total_time_minutes: Optional[int] = Field(default=None, ge=0, description="Total time in minutes")

    ingredient_groups: List[IngredientGroup] = Field(default_factory=list, description="Grouped ingredients")
    instruction_groups: List[InstructionGroup] = Field(
        default_factory=list,
        description="Grouped instructions (e.g., 'הכנה')",
    )

    notes: List[str] = Field(default_factory=list, description="Additional notes")
    images: List[str] = Field(default_factory=list, description="Recipe image URLs")
    nutrition: Optional[Nutrition] = Field(default=None, description="Nutritional information")

    @computed_field
    @property
    def ingredients(self) -> List[str]:
        """
        Flat list derived from ingredient_groups.
        Keeps your old key ('ingredients') without storing duplicate truth.
        """
        out: List[str] = []
        for g in self.ingredient_groups:
            for ing in g.ingredients:
                if ing.raw:
                    out.append(ing.raw)
                else:
                    parts = [ing.amount, ing.name]
                    out.append(" ".join(p for p in parts if p))
        return out

    model_config = ConfigDict(
        **APIModel.model_config,
        json_schema_extra={
            "example": {
                "id": None,
                "title": "רולדת טירמיסו יפיפייה",
                "source": "https://kerenagam.co.il/רולדת-טירמיסו-יפיפייה/",
                "language": "he",
                "servings": {
                    "amount": "1",
                    "unit": "רולדה",
                    "raw": "רולדה אחת",
                },
                "prepTimeMinutes": None,
                "cookTimeMinutes": None,
                "totalTimeMinutes": None,
                "ingredientGroups": [
                    {
                        "name": "לבסיס",
                        "ingredients": [
                            {
                                "amount": "30",
                                "name": "בישקוטים",
                                "preparation": None,
                                "raw": "30 בישקוטים",
                            },
                            {
                                "amount": "1 כוס",
                                "name": "קפה חזק",
                                "preparation": None,
                                "raw": "1 כוס קפה חזק",
                            },
                        ],
                    },
                    {
                        "name": "לקרם",
                        "ingredients": [
                            {
                                "amount": "250 מ״ל",
                                "name": "שמנת להקצפה",
                                "preparation": None,
                                "raw": "שמנת להקצפה 250 מ״ל",
                            },
                            {
                                "amount": "5 כפות",
                                "name": "אבקת סוכר",
                                "preparation": None,
                                "raw": "5 כפות אבקת סוכר",
                            },
                        ],
                    },
                ],
                # 'ingredients' is computed from ingredientGroups (kept for backward compatibility)
                "instructionGroups": [
                    {
                        "name": "הכנה",
                        "instructions": [
                            "פורסים ניילון נצמד על משטח.",
                            "טובלים בישקוטים בקפה ומסדרים שלוש שורות.",
                        ],
                    }
                ],
                "notes": ["מומלץ להכין את הרולדה יום מראש כדי שתתייצב היטב."],
                "images": ["https://example.com/main-image.jpg"],
                "nutrition": {
                    "calories": None,
                    "protein_g": None,
                    "fat_g": None,
                    "carbs_g": None,
                    "per": "slice",
                },
            }
        },
    )
