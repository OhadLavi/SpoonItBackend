"""Recipe Pydantic models."""

from typing import List, Optional
from pydantic import BaseModel, Field


class Ingredient(BaseModel):
    """Single ingredient model."""

    quantity: Optional[str] = Field(None, description="Quantity/amount (e.g., '1', '2.5', '30')")
    name: str = Field(..., description="Ingredient name")
    unit: Optional[str] = Field(None, description="Unit of measurement (e.g., 'כוס', 'כפות', 'מ״ל', 'גרם')")
    preparation: Optional[str] = Field(None, description="Preparation notes (e.g., 'chopped', 'diced', 'at room temperature')")
    raw: Optional[str] = Field(None, description="Original raw ingredient text for reference")


class IngredientGroup(BaseModel):
    """Group of ingredients (e.g., 'For the base', 'For the cream')."""

    name: Optional[str] = Field(None, description="Group name (e.g., 'For the base')")
    ingredients: List[Ingredient] = Field(..., description="List of ingredients in this group")


class InstructionGroup(BaseModel):
    """Group of instructions (e.g., 'הכנת הבצק', 'הגשה')."""

    name: Optional[str] = Field(None, description="Group name (e.g., 'הכנת הבצק', 'הגשה')")
    instructions: List[str] = Field(..., description="List of instructions in this group")


class Nutrition(BaseModel):
    """Nutritional information."""

    calories: Optional[float] = Field(None, description="Calories per serving")
    protein_g: Optional[float] = Field(None, description="Protein in grams")
    fat_g: Optional[float] = Field(None, description="Fat in grams")
    carbs_g: Optional[float] = Field(None, description="Carbohydrates in grams")
    per: Optional[str] = Field(None, description="Per what (e.g., 'slice', 'serving')")


class Recipe(BaseModel):
    """Unified recipe model returned by all endpoints."""

    id: Optional[str] = Field(None, description="Recipe ID (null for extracted recipes)")
    title: Optional[str] = Field(None, description="Recipe title")
    source: Optional[str] = Field(None, description="Source URL or identifier")

    language: Optional[str] = Field(None, description="Language code (e.g., 'he', 'en')")
    servings: Optional[str] = Field(None, description="Number of servings")
    prepTimeMinutes: Optional[int] = Field(None, description="Preparation time in minutes")
    cookTimeMinutes: Optional[int] = Field(None, description="Cooking time in minutes")
    totalTimeMinutes: Optional[int] = Field(None, description="Total time in minutes")
    ingredientGroups: List[IngredientGroup] = Field(
        default_factory=list, description="Grouped ingredients"
    )
    ingredients: List[str] = Field(
        default_factory=list, description="Flat list of all ingredients (raw text)"
    )
    instructionGroups: List[InstructionGroup] = Field(
        default_factory=list, description="Grouped instructions (e.g., 'הכנת הבצק', 'הגשה')"
    )
    notes: List[str] = Field(default_factory=list, description="Additional notes")
    images: List[str] = Field(default_factory=list, description="Recipe image URLs")
    nutrition: Optional[Nutrition] = Field(None, description="Nutritional information")

    class Config:
        """Pydantic config."""

        json_schema_extra = {
            "example": {
                "id": None,
                "title": "רולדת טירמיסו יפיפייה",
                "source": "https://kerenagam.co.il/רולדת-טירמיסו-יפיפייה/",

                "language": "he",
                "servings": "רולדה אחת",
                "prepTimeMinutes": None,
                "cookTimeMinutes": None,
                "totalTimeMinutes": None,
                "ingredientGroups": [
                    {
                        "name": "לבסיס",
                        "ingredients": [
                            {
                                "quantity": "30",
                                "name": "בישקוטים",
                                "unit": None,
                                "preparation": None,
                                "raw": "30 בישקוטים"
                            },
                            {
                                "quantity": "1",
                                "name": "קפה חזק",
                                "unit": "כוס",
                                "preparation": None,
                                "raw": "1 כוס קפה חזק"
                            }
                        ],
                    },
                    {
                        "name": "לקרם",
                        "ingredients": [
                            {
                                "quantity": "1",
                                "name": "שמנת להקצפה",
                                "unit": "מ״ל",
                                "preparation": None,
                                "raw": "1 שמנת להקצפה 250 מ״ל"
                            },
                            {
                                "quantity": "5",
                                "name": "אבקת סוכר",
                                "unit": "כפות",
                                "preparation": None,
                                "raw": "5 כפות אבקת סוכר"
                            }
                        ],
                    },
                ],
                "ingredients": ["30 בישקוטים", "1 כוס קפה חזק"],
                "instructionGroups": [
                    {
                        "name": "הכנה",
                        "instructions": ["פורסים ניילון נצמד על משטח.", "טובלים בישקוטים בקפה ומסדרים שלוש שורות."]
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
        }

