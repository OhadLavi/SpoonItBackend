"""Recipe Pydantic models."""

from typing import List, Optional
from pydantic import BaseModel, Field, HttpUrl


class Ingredient(BaseModel):
    """Single ingredient model."""

    raw: str = Field(..., description="Raw ingredient text as it appears in the recipe")


class IngredientGroup(BaseModel):
    """Group of ingredients (e.g., 'For the base', 'For the cream')."""

    name: Optional[str] = Field(None, description="Group name (e.g., 'For the base')")
    ingredients: List[Ingredient] = Field(..., description="List of ingredients in this group")


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
    description: Optional[str] = Field(None, description="Recipe description")
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
    instructions: List[str] = Field(default_factory=list, description="Cooking instructions")
    notes: List[str] = Field(default_factory=list, description="Additional notes")
    imageUrl: Optional[HttpUrl] = Field(None, description="Main recipe image URL")
    images: List[str] = Field(default_factory=list, description="All recipe image URLs")
    nutrition: Optional[Nutrition] = Field(None, description="Nutritional information")
    createdAt: Optional[str] = Field(None, description="Creation timestamp (null for extracted)")
    updatedAt: Optional[str] = Field(None, description="Update timestamp (null for extracted)")

    class Config:
        """Pydantic config."""

        json_schema_extra = {
            "example": {
                "id": None,
                "title": "רולדת טירמיסו יפיפייה",
                "description": "רולדת טירמיסו/רולדה אחת. מתכון רולדה בסגנון טירמיסו עם קרם מסקרפונה.",
                "source": "https://kerenagam.co.il/רולדת-טירמיסו-יפיפייה/",
                "language": "he",
                "servings": "רולדה אחת",
                "prepTimeMinutes": None,
                "cookTimeMinutes": None,
                "totalTimeMinutes": None,
                "ingredientGroups": [
                    {
                        "name": "לבסיס",
                        "ingredients": [{"raw": "30 בישקוטים"}, {"raw": "1 כוס קפה חזק"}],
                    },
                    {
                        "name": "לקרם",
                        "ingredients": [
                            {"raw": "1 שמנת להקצפה 250 מ״ל"},
                            {"raw": "5 כפות אבקת סוכר"},
                        ],
                    },
                ],
                "ingredients": ["30 בישקוטים", "1 כוס קפה חזק"],
                "instructions": ["פורסים ניילון נצמד על משטח.", "טובלים בישקוטים בקפה ומסדרים שלוש שורות."],
                "notes": ["מומלץ להכין את הרולדה יום מראש כדי שתתייצב היטב."],
                "imageUrl": "https://example.com/main-image.jpg",
                "images": ["https://example.com/main-image.jpg"],
                "nutrition": {
                    "calories": None,
                    "protein_g": None,
                    "fat_g": None,
                    "carbs_g": None,
                    "per": "slice",
                },
                "createdAt": None,
                "updatedAt": None,
            }
        }

