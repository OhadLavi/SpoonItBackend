# routes/chat.py
"""Chat endpoint for recipe generation."""

import json
from fastapi import APIRouter, HTTPException

from config import logger, GEMINI_API_KEY
from models import ChatRequest
from services.gemini_service import get_gemini_model
from services.prompt_service import create_chat_system_prompt

router = APIRouter()


@router.post("/chat")
async def chat(request: ChatRequest):
    """Chat endpoint for recipe-focused conversations."""
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY not configured")
    
    try:
        model = get_gemini_model()
        
        # Recipe-focused system prompt
        sys_prompt = create_chat_system_prompt(request.language)
        
        # Build conversation history if provided
        history = request.conversation_history or []
        
        # Build the full conversation prompt
        conversation_parts = [sys_prompt]
        
        # Add conversation history (only if exists)
        if history:
            conversation_parts.append("Previous conversation:")
            for msg in history:
                role = msg.get("role", "user")
                content = msg.get("content", "")
                if content:
                    conversation_parts.append(f"{role.capitalize()}: {content}")
            conversation_parts.append("\nCurrent message:")
        
        # Add current message
        conversation_parts.append(f"User: {request.message}")
        conversation_parts.append("Assistant:")
        
        prompt = "\n\n".join(conversation_parts)
        
        try:
            response = model.generate_content(prompt)
            response_text = (response.text or "").strip()
        except Exception as gen_error:
            logger.error("[CHAT] Gemini API error: %s", gen_error, exc_info=True)
            raise HTTPException(
                status_code=500,
                detail=f"Failed to generate response from Gemini: {str(gen_error)}"
            )
        
        if not response_text:
            logger.warning("[CHAT] Empty response from Gemini")
            raise HTTPException(status_code=500, detail="Empty response from Gemini")
        
        # Try to parse as JSON recipe, if it starts with { or contains recipe structure
        is_recipe = False
        recipe_data = None
        
        if "{" in response_text:
            try:
                # Strip code fences if present
                json_text = response_text
                if "```" in json_text:
                    lines = json_text.split("\n")
                    if lines and lines[0].startswith("```"):
                        lines = lines[1:]
                    if lines and lines[-1].strip() == "```":
                        lines = lines[:-1]
                    json_text = "\n".join(lines).strip()
                
                # Try to extract JSON from text
                start_idx = json_text.find("{")
                end_idx = json_text.rfind("}") + 1
                if start_idx != -1 and end_idx > start_idx:
                    json_str = json_text[start_idx:end_idx]
                    recipe_data = json.loads(json_str)
                    is_recipe = True
            except Exception:
                # Not a valid recipe JSON, treat as normal text response
                pass
        
        return {
            "response": response_text,
            "model": "gemini-2.5-flash",
            "is_recipe": is_recipe,
            "recipe": recipe_data if is_recipe else None
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error("[CHAT] error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail=f"Chat request failed: {str(e)}")

