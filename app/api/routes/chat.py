"""Chat endpoint for recipe-focused conversations."""

import logging
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel

from app.api.dependencies import get_recipe_extractor
from app.core.request_id import get_request_id
from app.middleware.rate_limit import rate_limit_dependency
from app.models.recipe import Recipe
from app.services.recipe_extractor import RecipeExtractor
from app.utils.exceptions import GeminiError, ValidationError

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/chat", tags=["chat"])


class ChatRequest(BaseModel):
    """Request model for chat endpoint."""

    message: str
    language: str = "he"
    conversation_history: Optional[List[dict]] = None


class ChatResponse(BaseModel):
    """Response model for chat endpoint."""

    response: str
    model: str
    is_recipe: bool
    recipe: Optional[dict] = None


@router.post("", response_model=ChatResponse)
async def chat(
    request: Request,
    chat_request: ChatRequest,
    _: None = Depends(rate_limit_dependency),
    recipe_extractor: RecipeExtractor = Depends(get_recipe_extractor),
) -> ChatResponse:
    """
    Chat endpoint for recipe-focused conversations.

    - **message**: User's message/request
    - **language**: Language code (default: "he")
    - **conversation_history**: Optional conversation history
    - Returns chat response with recipe if applicable
    """
    # Log route-specific parameters
    logger.info(
        f"Route /chat called",
        extra={
            "request_id": getattr(request.state, "request_id", None),
            "route": "/chat",
            "params": {
                "message": chat_request.message[:200],  # Truncate long messages
                "language": chat_request.language,
                "has_history": bool(chat_request.conversation_history),
                "history_length": len(chat_request.conversation_history) if chat_request.conversation_history else 0,
            },
        },
    )
    
    try:
        # Build prompt from message and history
        prompt_parts = []
        
        # Add system prompt
        system_prompt = (
            "You are a creative and helpful chef assistant. "
            "Your goal is to help users find recipes, plan meals, and cook with what they have. "
            "If the user provides a list of ingredients, suggest recipes that can be made with them. "
            "If the user asks for a specific recipe, provide it. "
            "Maintain a friendly and encouraging tone. "
            "When the user asks for a recipe, respond with a recipe in JSON format. "
            "Otherwise, provide a helpful text response."
        )
        prompt_parts.append(system_prompt)
        
        # Add conversation history if provided
        if chat_request.conversation_history:
            prompt_parts.append("Conversation History:")
            for msg in chat_request.conversation_history:
                role = msg.get("role", "user")
                content = msg.get("content", "")
                if content:
                    prompt_parts.append(f"{role.capitalize()}: {content}")
        
        # Add current message
        prompt_parts.append(f"User: {chat_request.message}")
        
        # Build the instruction for recipe generation
        prompt_parts.append(
            f"Based on the user's request, generate a recipe in JSON format matching this exact structure:\n\n"
            f"{{\n"
            f'  "title": "Recipe title",\n'
            f'  "description": "Brief recipe description",\n'
            f'  "language": "{chat_request.language}",\n'
            f'  "servings": "Number of servings",\n'
            f'  "prepTimeMinutes": number or null,\n'
            f'  "cookTimeMinutes": number or null,\n'
            f'  "totalTimeMinutes": number or null,\n'
            f'  "ingredientGroups": [\n'
            f'    {{\n'
            f'      "name": "Group name or null",\n'
            f'      "ingredients": [\n'
            f'        {{"raw": "ingredient with amount"}}\n'
            f'      ]\n'
            f'    }}\n'
            f'  ],\n'
            f'  "ingredients": ["flat list of all ingredients with amounts"],\n'
            f'  "instructionGroups": [\n'
            f'    {{\n'
            f'      "name": "Group name or null",\n'
            f'      "instructions": ["detailed step 1", "detailed step 2", ...]\n'
            f'    }}\n'
            f'  ],\n'
            f'  "notes": ["helpful tip 1", ...] or [],\n'
            f'  "imageUrl": null,\n'
            f'  "images": [],\n'
            f'  "nutrition": {{\n'
            f'    "calories": number or null,\n'
            f'    "protein_g": number or null,\n'
            f'    "fat_g": number or null,\n'
            f'    "carbs_g": number or null,\n'
            f'    "per": "serving" or null\n'
            f'  }}\n'
            f"}}\n\n"
            f"Return ONLY valid JSON, no markdown, no code blocks, no explanations."
        )
        
        full_prompt = "\n\n".join(prompt_parts)
        
        # Try to extract/generate recipe from the message
        # For now, we'll treat all messages as potential recipe requests
        try:
            # Try to generate a recipe from the message
            # We pass the full prompt as the "ingredients" list to the extractor for now, 
            # as the extractor expects a list of strings. 
            # Ideally, the extractor should have a dedicated method for chat-based generation.
            # But for this implementation, we rely on the extractor's ability to handle the prompt.
            # A better approach would be to have a dedicated chat method in GeminiService.
            # However, to minimize refactoring risk, we'll use the existing flow but with the enhanced prompt.
            
            # NOTE: The current recipe_extractor.generate_from_ingredients might be too specific 
            # (it wraps input in "Create a recipe with these ingredients...").
            # We might need to bypass it or adjust it. 
            # Let's check recipe_extractor.py again.
            
            # Actually, let's look at how we can use the history better.
            # The recipe_extractor.generate_from_ingredients calls gemini_service.generate_recipe.
            # Let's see if we can pass the full prompt there.
            
            # Use the new generate_from_text method which accepts the full prompt directly
            recipe = await recipe_extractor.generate_from_text(full_prompt)
            
            return ChatResponse(
                response="Here's a recipe based on your request:",
                model="gemini-2.5-flash-lite",
                is_recipe=True,
                recipe=recipe.model_dump(),
            )
        except Exception as e:
            # Log the specific error that caused the fallback
            logger.warning(f"Chat recipe generation failed: {str(e)}")
            
            # Localize fallback message
            fallback_msg = (
                f"I understand you're asking about: {chat_request.message}. "
                "Please provide specific ingredients or a recipe URL for me to help you better."
            )
            
            if chat_request.language == "he":
                fallback_msg = (
                    f"הבנתי שאתה שואל על: {chat_request.message}. "
                    "אנא ספק רשימת מצרכים או קישור למתכון כדי שאוכל לעזור לך טוב יותר."
                )

            return ChatResponse(
                response=fallback_msg,
                model="gemini-2.5-flash-lite",
                is_recipe=False,
            )

    except ValidationError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "Invalid request", "detail": str(e)},
        ) from e
    except GeminiError as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"error": "Failed to process chat request", "detail": str(e)},
        ) from e
    except Exception as e:
        logger.error(f"Unexpected error in chat: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"error": "Internal server error", "detail": "An unexpected error occurred"},
        ) from e

