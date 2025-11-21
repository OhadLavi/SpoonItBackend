"""Chat endpoint for recipe-focused conversations."""

import logging
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel

from app.api.dependencies import get_recipe_extractor
from app.middleware.auth import verify_api_key
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
    api_key: str = Depends(verify_api_key),
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
    try:
        # Build prompt from message and history
        prompt_parts = []
        
        # Add system prompt
        system_prompt = (
            "You are a helpful recipe assistant. "
            "When the user asks for a recipe, respond with a recipe in JSON format. "
            "Otherwise, provide helpful cooking advice."
        )
        prompt_parts.append(system_prompt)
        
        # Add conversation history if provided
        if chat_request.conversation_history:
            for msg in chat_request.conversation_history:
                role = msg.get("role", "user")
                content = msg.get("content", "")
                if content:
                    prompt_parts.append(f"{role.capitalize()}: {content}")
        
        # Add current message
        prompt_parts.append(f"User: {chat_request.message}")
        prompt_parts.append(
            "If this is a recipe request, respond with a SINGLE JSON object for one recipe, no extra text. "
            "Otherwise, provide a helpful text response."
        )
        
        full_prompt = "\n\n".join(prompt_parts)
        
        # Try to extract/generate recipe from the message
        # For now, we'll treat all messages as potential recipe requests
        try:
            # Try to generate a recipe from the message
            recipe = await recipe_extractor.generate_from_ingredients([chat_request.message])
            
            return ChatResponse(
                response="Here's a recipe based on your request:",
                model="gemini-1.5-pro",
                is_recipe=True,
                recipe=recipe.model_dump(),
            )
        except Exception:
            # If recipe generation fails, return a text response
            # In a full implementation, you'd use Gemini's chat API here
            return ChatResponse(
                response=f"I understand you're asking about: {chat_request.message}. "
                        "Please provide specific ingredients or a recipe URL for me to help you better.",
                model="gemini-1.5-pro",
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

