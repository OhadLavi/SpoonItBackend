# models.py
"""Pydantic models for request/response validation."""

from typing import Optional, List
from pydantic import BaseModel, Field


class ChatRequest(BaseModel):
    """Request model for chat endpoint."""
    message: str
    language: str = "en"
    conversation_history: Optional[List[dict]] = None


class RecipeExtractionRequest(BaseModel):
    """Request model for recipe extraction from URL."""
    url: str
    html_content: Optional[str] = None


class ImageExtractionRequest(BaseModel):
    """Request model for recipe extraction from image."""
    image_data: str  # base64 (with or without data URI prefix)


class CustomRecipeRequest(BaseModel):
    """Request model for custom recipe generation."""
    groceries: str
    description: str


class IngredientGroup(BaseModel):
    """Model for grouped ingredients with category."""
    category: str = ""
    ingredients: List[str] = Field(default_factory=list, min_length=0)


class RecipeModel(BaseModel):
    """Complete recipe model with all fields."""
    title: str = ""
    description: str = ""
    ingredients: List[str] = Field(default_factory=list, min_length=0)
    ingredientsGroups: Optional[List[IngredientGroup]] = None
    instructions: List[str] = Field(default_factory=list, min_length=0)
    prepTime: int = 0
    cookTime: int = 0
    servings: int = 1
    tags: List[str] = Field(default_factory=list, min_length=0)
    notes: str = ""
    source: str = ""
    imageUrl: str = ""

