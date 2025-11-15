# routes/chat.py
"""Chat endpoint for recipe-focused conversations, returning JSON recipes."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException

from config import GEMINI_API_KEY, logger
from models import ChatRequest
from services.gemini_service import generate_json_from_prompt
from services.prompt_service import create_chat_system_prompt
from utils.normalization import normalize_recipe_fields

router = APIRouter()


@router.post("/chat")
async def chat(request: ChatRequest):
    """
    Chat endpoint: user sends free-text request (ingredients + style),
    backend returns ONE recipe JSON (via Gemini).
    """
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY not configured")

    sys_prompt = create_chat_system_prompt(request.language)

    history_parts: list[str] = []
    if request.conversation_history:
        for msg in request.conversation_history:
            role = msg.get("role", "user")
            content = msg.get("content", "")
            if content:
                history_parts.append(f"{role.capitalize()}: {content}")

    history_block = "\n".join(history_parts) if history_parts else "(no previous messages)"

    prompt = (
        f"{sys_prompt}\n\n"
        f"Conversation so far:\n{history_block}\n\n"
        f"User: {request.message}\n\n"
        "Remember: respond with a SINGLE JSON object for one recipe, no extra text."
    )

    try:
        recipe_dict = await generate_json_from_prompt(
            prompt,
            max_output_tokens=4096,
            temperature=0.5,
            label="chat",
        )
    except Exception as e:
        logger.error("[CHAT] Gemini error: %s", e, exc_info=True)
        raise

    recipe_model = normalize_recipe_fields(recipe_dict)

    return {
        "recipe": recipe_model.model_dump(),
    }
