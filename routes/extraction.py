# routes/extraction.py
"""Recipe extraction endpoints for URL, image, and custom recipes."""

import base64
import json
import re
from fastapi import APIRouter, HTTPException, UploadFile, File
import httpx

from config import logger, GEMINI_API_KEY, OLLAMA_API_URL, MODEL_NAME, HTTP_TIMEOUT
from models import (
    RecipeExtractionRequest,
    ImageExtractionRequest,
    CustomRecipeRequest,
    IngredientGroup,
    RecipeModel,
)
from services.fetcher_service import fetch_html_content
from services.gemini_service import get_gemini_model
from services.ocr_service import extract_text_from_image
from services.prompt_service import (
    create_recipe_extraction_prompt,
    create_extraction_prompt,
    create_custom_recipe_prompt,
)
from utils.json_repair import extract_and_parse_llm_json
from utils.normalization import normalize_recipe_fields
from errors import APIError

router = APIRouter()


@router.post("/extract_recipe")
async def extract_recipe(req: RecipeExtractionRequest):
    """Extract recipe from URL using Gemini API."""
    url = req.url.strip()
    logger.info("[FLOW] extract_recipe START | url=%s", url)
    if not url.startswith("http"):
        raise HTTPException(status_code=400, detail="Invalid URL")

    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY not configured")

    try:
        if req.html_content:
            logger.info("[FLOW] using HTML content provided by client, length=%d", len(req.html_content))
            html = req.html_content
            html = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL | re.IGNORECASE)
            html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.DOTALL | re.IGNORECASE)
            page_text = re.sub(r'<[^>]+>', ' ', html)
            page_text = re.sub(r'\s+', ' ', page_text).strip()
            if len(page_text.encode('utf-8')) > 50_000:
                page_text = page_text[:50_000]
        else:
            try:
                page_text = await fetch_html_content(url)
                logger.info("[FLOW] fetched page text, length=%d", len(page_text))
            except APIError as e:
                if e.status_code == 403 and e.details.get("code") in ("FETCH_FORBIDDEN", "PLAYWRIGHT_UNAVAILABLE"):
                    # Return a clear 403 with instructions for client-side fetch fallback
                    raise HTTPException(
                        status_code=403,
                        detail={
                            "code": e.details.get("code"),
                            "message": (
                                "The website is blocking Cloud Run or Playwright is unavailable. "
                                "Please fetch the page on the client and resend as html_content."
                            ),
                            "url": url,
                        },
                    )
                raise HTTPException(status_code=e.status_code, detail=e.message)

        # Use Gemini API
        model = get_gemini_model()
        prompt = create_extraction_prompt(url, page_text)
        response = model.generate_content(prompt)
        response_text = (response.text or "").strip()

        if not response_text:
            logger.error("[LLM] empty response. First 160 page_text chars: %r", page_text[:160])
            raise HTTPException(
                status_code=502,
                detail={"code": "LLM_EMPTY", "message": "Model returned empty response"}
            )

        # Strip code fences (if any)
        if response_text.startswith("```"):
            lines = response_text.split("\n")
            if lines and lines[0].startswith("```"):
                lines = lines[1:]
            if lines and lines[-1].strip() == "```":
                lines = lines[:-1]
            response_text = "\n".join(lines).strip()

        # Parse JSON with repair fallback
        try:
            recipe_dict = json.loads(response_text)
        except Exception:
            try:
                recipe_dict = await extract_and_parse_llm_json(response_text)
            except Exception as e:
                logger.error("[FLOW] JSON parse error (after repair). Raw head: %r", response_text[:220])
                raise HTTPException(
                    status_code=500,
                    detail={
                        "code": "LLM_JSON_PARSE",
                        "message": f"Failed to parse JSON response from Gemini: {str(e)}",
                        "raw_head": response_text[:500],
                    },
                )

        if not recipe_dict.get("source"):
            recipe_dict["source"] = url

        # Number instructions (remove existing numbering first)
        instructions = recipe_dict.get("instructions", [])
        numbered_instructions = []
        for i, instruction in enumerate(instructions, 1):
            instruction_str = str(instruction).strip()
            instruction_str = re.sub(r'^\d+[\.\)]\s*', '', instruction_str)
            numbered_instructions.append(f"{i}. {instruction_str}")
        recipe_dict["instructions"] = numbered_instructions

        # ingredientsGroups (optional -> Pydantic validation)
        ingredients_groups = None
        if "ingredientsGroups" in recipe_dict and recipe_dict["ingredientsGroups"]:
            try:
                ingredients_groups = [
                    IngredientGroup(
                        category=(group.get("category", "") if isinstance(group, dict) else ""),
                        ingredients=(group.get("ingredients", []) if isinstance(group, dict) else []),
                    )
                    for group in recipe_dict["ingredientsGroups"]
                ]
            except Exception as e:
                logger.warning("Failed to parse ingredientsGroups: %s", e)
                ingredients_groups = None

        recipe_model = RecipeModel(
            title=recipe_dict.get("title", ""),
            description=recipe_dict.get("description", ""),
            ingredients=recipe_dict.get("ingredients", []),
            ingredientsGroups=ingredients_groups,
            instructions=numbered_instructions,
            prepTime=int(recipe_dict.get("prepTime", 0) or 0),
            cookTime=int(recipe_dict.get("cookTime", 0) or 0),
            servings=int(recipe_dict.get("servings", 1) or 1),
            tags=recipe_dict.get("tags", []),
            notes=recipe_dict.get("notes", ""),
            source=recipe_dict.get("source", url),
            imageUrl=recipe_dict.get("imageUrl", ""),
        )

        logger.info(
            "[FLOW] done via Gemini | title='%s' ings=%d steps=%d prep=%d cook=%d",
            recipe_model.title, len(recipe_model.ingredients), len(recipe_model.instructions),
            recipe_model.prepTime, recipe_model.cookTime
        )
        return recipe_model.model_dump()

    except HTTPException:
        raise
    except Exception as e:
        logger.error("[FLOW] unexpected error: %s", e, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={"code": "UNEXPECTED", "message": f"Error calling Gemini API: {str(e)}"},
        )


@router.post("/extract_recipe_from_image")
async def extract_recipe_from_image(req: ImageExtractionRequest):
    """Extract recipe from base64 encoded image using OCR and Ollama."""
    try:
        data = req.image_data
        if "," in data:
            data = data.split(",", 1)[1]
        image_bytes = base64.b64decode(data)
        text = extract_text_from_image(image_bytes)
        if not text or len(text) < 40:
            raise HTTPException(status_code=400, detail="Not enough text extracted from image")

        prompt = create_recipe_extraction_prompt(text)
        payload = {
            "model": MODEL_NAME,
            "prompt": prompt,
            "stream": False,
            "format": "json",
            "options": {"temperature": 0, "num_ctx": 4096, "top_k": 40, "top_p": 0.9},
        }
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
            r = await client.post(OLLAMA_API_URL, json=payload)
            r.raise_for_status()
            data = r.json()
        output = data.get("response", "")

        try:
            recipe_dict = json.loads(output)
        except Exception:
            recipe_dict = await extract_and_parse_llm_json(output)
        recipe_model = normalize_recipe_fields(recipe_dict)
        return recipe_model.model_dump()

    except HTTPException:
        raise
    except Exception as e:
        logger.error("[IMG] error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error processing image: {str(e)}")


@router.post("/upload_recipe_image")
async def upload_recipe_image(file: UploadFile = File(...)):
    """Upload and extract recipe from multipart image file."""
    try:
        contents = await file.read()
        text = extract_text_from_image(contents)
        if not text or len(text) < 40:
            raise HTTPException(status_code=400, detail="Not enough text extracted from image")

        prompt = create_recipe_extraction_prompt(text)
        payload = {
            "model": MODEL_NAME,
            "prompt": prompt,
            "stream": False,
            "format": "json",
            "options": {"temperature": 0, "num_ctx": 4096, "top_k": 40, "top_p": 0.9},
        }
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
            r = await client.post(OLLAMA_API_URL, json=payload)
            r.raise_for_status()
            data = r.json()
        output = data.get("response", "")

        try:
            recipe_dict = json.loads(output)
        except Exception:
            recipe_dict = await extract_and_parse_llm_json(output)
        recipe_model = normalize_recipe_fields(recipe_dict)
        return recipe_model.model_dump()

    except HTTPException:
        raise
    except Exception as e:
        logger.error("[UPLOAD] error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error processing uploaded image: {str(e)}")


@router.post("/custom_recipe")
async def custom_recipe(req: CustomRecipeRequest):
    """Generate custom recipe from groceries and description using Ollama."""
    try:
        prompt = create_custom_recipe_prompt(req.groceries, req.description)
        payload = {
            "model": MODEL_NAME,
            "prompt": prompt,
            "stream": False,
            "format": "json",
            "options": {"temperature": 0.5, "num_ctx": 4096, "top_k": 50, "top_p": 0.95},
        }
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
            r = await client.post(OLLAMA_API_URL, json=payload)
            r.raise_for_status()
            data = r.json()
        output = data.get("response", "")

        try:
            recipe_dict = json.loads(output)
        except Exception:
            recipe_dict = await extract_and_parse_llm_json(output)
        recipe_model = normalize_recipe_fields(recipe_dict)
        return recipe_model.model_dump()

    except HTTPException:
        raise
    except Exception as e:
        logger.error("[CUSTOM] error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail="An unexpected error occurred during custom recipe generation")

