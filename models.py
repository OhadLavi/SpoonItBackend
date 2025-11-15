# models.py
"""Pydantic models for request/response validation."""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------
class ChatRequest(BaseModel):
    """Request model for the chat endpoint.

    `message` is the latest user utterance. `conversation_history` is optional
    and can contain a list of {role, content} dicts.
    """

    message: str
    language: str = "he"
    conversation_history: Optional[List[Dict[str, Any]]] = None


class RecipeExtractionRequest(BaseModel):
    """Recipe extraction from URL (optionally with client-provided HTML)."""

    url: str
    html_content: Optional[str] = None


class ImageExtractionRequest(BaseModel):
    """Recipe extraction from base64-encoded image."""

    image_data: str  # base64 string, with or without data URI prefix


class CustomRecipeRequest(BaseModel):
    """Generate a custom recipe from given groceries and description."""

    groceries: str
    description: str


# ---------------------------------------------------------------------------
# Recipe models
# ---------------------------------------------------------------------------
class IngredientGroup(BaseModel):
    """Group of ingredients under a specific category header."""

    category: str = ""
    ingredients: List[str] = Field(default_factory=list)


class RecipeModel(BaseModel):
    """Canonical recipe struct returned to the frontend."""

    title: str = ""
    description: str = ""
    ingredients: List[str] = Field(default_factory=list)
    ingredientsGroups: Optional[List[IngredientGroup]] = None
    instructions: List[str] = Field(default_factory=list)
    prepTime: int = 0  # minutes
    cookTime: int = 0  # minutes
    servings: int = 1
    tags: List[str] = Field(default_factory=list)
    notes: str = ""
    source: str = ""
    imageUrl: str = ""
    images: Optional[List[str]] = None
