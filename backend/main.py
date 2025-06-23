from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel
import uvicorn
import json
import re
import logging
from typing import Optional, Dict, Any, List
from bs4 import BeautifulSoup
import io
import base64
import pytesseract
from PIL import Image
from playwright.async_api import async_playwright

# --- Logging configuration ---
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('recipe_keeper.log', encoding='utf-8'),
        logging.StreamHandler()
    ],
    encoding='utf-8'
)
logger = logging.getLogger(__name__)

# --- Custom error class ---
class APIError(Exception):
    def __init__(self, message: str, status_code: int = 500, details: Optional[Dict[str, Any]] = None):
        self.message = message
        self.status_code = status_code
        self.details = details or {}
        super().__init__(self.message)

# --- Request schemas ---
class ChatRequest(BaseModel):
    message: str
    language: str = "en"  # Default to English

class RecipeExtractionRequest(BaseModel):
    url: str

class ImageExtractionRequest(BaseModel):
    image_data: str  # Base64 encoded image data

# Add new request schema for custom recipe generation
class CustomRecipeRequest(BaseModel):
    groceries: str
    description: str

# --- Ollama configuration ---
OLLAMA_API_URL = "http://127.0.0.1:11434/api/generate"
MODEL_NAME = "gemma3:4b"

# --- Helper functions ---
HEBREW_NUMBERS = {
    'אחד': 1, 'אחת': 1,
    'שתיים': 2, 'שניים': 2, 'שתים': 2,
    'שלוש': 3, 'שלושה': 3,
    'ארבע': 4, 'ארבעה': 4,
    'חמש': 5, 'חמישה': 5,
    'שש': 6, 'שישה': 6,
    'שבע': 7, 'שבעה': 7,
    'שמונה': 8,
    'תשע': 9,
    'עשר': 10
}

def safe_strip(value: Any) -> str:
    """
    Convert value to string (if not None) and strip whitespace.
    If value is None, return "".
    """
    if value is None:
        return ""
    return str(value).strip()

def clean_html(text: Any) -> str:
    """
    Convert text (which may be None or a string) to a stripped string with HTML removed.
    """
    s = safe_strip(text)
    if not s:
        return ""
    return BeautifulSoup(s, 'html.parser').get_text(separator=' ', strip=True)

def convert_to_int(num_str: Any) -> int:
    s = safe_strip(num_str)
    if not s:
        return 0
    try:
        return int(s)
    except ValueError:
        pass
    for word, val in HEBREW_NUMBERS.items():
        if word in s:
            return val
    return 0

def parse_time_value(time_str: Any) -> int:
    s = clean_html(time_str).lower()
    if not s:
        return 0
    total_minutes = 0
    hour_match = re.search(r'(\d+|\w+)\s*(?:שעה(?:ות)?|hr)', s)
    if hour_match:
        total_minutes += convert_to_int(hour_match.group(1)) * 60
    minute_match = re.search(r'(\d+|\w+)\s*(?:דקה(?:ות)?|min)', s)
    if minute_match:
        total_minutes += convert_to_int(minute_match.group(1))
    return total_minutes

def parse_servings(servings_str: Any) -> int:
    s = clean_html(servings_str).lower()
    if not s:
        return 1
    digit_match = re.search(r'(\d+)', s)
    if digit_match:
        return int(digit_match.group(1))
    for word, val in HEBREW_NUMBERS.items():
        if word in s:
            return val
    return 1

def ensure_list(value: Any) -> list:
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return list(value.values())
    return []

def extract_unique_lines(lines: list) -> list:
    seen = set()
    unique = []
    for line in lines:
        key = line.lower()
        if key not in seen:
            seen.add(key)
            unique.append(line)
    return unique

def remove_exact_duplicates(seq: List[str]) -> List[str]:
    """
    Remove repeated lines exactly, preserving order.
    Keeps the first occurrence, removes subsequent identical lines.
    """
    seen = set()
    output = []
    for item in seq:
        if item not in seen:
            seen.add(item)
            output.append(item)
    return output

def normalize_ingredient(item: Any) -> str:
    """
    Convert an ingredient item to a single consistent string,
    calling safe_strip on subfields to avoid NoneType errors.
    """
    if item is None:
        return ""
    if isinstance(item, str):
        return clean_html(item)

    if isinstance(item, dict):
        name = clean_html(item.get('name') or item.get('item'))
        quantity = clean_html(item.get('quantity'))
        unit = clean_html(item.get('unit'))
        notes = clean_html(item.get('notes'))

        parts = []
        if name:
            parts.append(name)
        if quantity:
            parts.append(quantity)
        if unit:
            parts.append(unit)
        if notes:
            parts.append(f"({notes})")

        return " ".join(parts).strip()

    return clean_html(item)

def extract_recipe_content(html_content: str) -> str:
    """
    Return the entire text, including scripts, so the LLM sees all instructions.
    """
    soup = BeautifulSoup(html_content, 'html.parser')
    text = soup.get_text(separator='\n', strip=True)
    if len(text) > 10000:
        text = text[:10000] + "\n... [content truncated]"
    logger.debug(f"Extracted recipe content length: {len(text)} characters")
    return text

def create_recipe_extraction_prompt(clean_text: str) -> str:
    """
    Prompt instructing the LLM to preserve every single instruction exactly as it appears (no merging or skipping),
    and absolutely NO made-up content or modifications.
    """
    prompt = (
        "You are a recipe extraction expert. You have ONE and ONLY ONE requirement: "
        "Return the recipe details exactly as they appear in the text, with NO invented or modified content. "
        "Do not add or remove anything from the ingredients or instructions.\n\n"
        "Extract EVERY SINGLE INSTRUCTION EXACTLY as it appears in the text (keeping the numbering if present), "
        "and return them without skipping or merging lines.\n\n"
        "Format your output as a strict JSON object:\n"
        "{\n"
        "  \"title\": \"Recipe title\",\n"
        "  \"description\": \"Brief description\",\n"
        "  \"ingredients\": [\"ingredient 1\", \"ingredient 2\", ...],\n"
        "  \"instructions\": [\"step 1\", \"step 2\", ...],\n"
        "  \"prepTime\": numberOfMinutes,\n"
        "  \"cookTime\": numberOfMinutes,\n"
        "  \"servings\": numberOfServings,\n"
        "  \"tags\": [\"tag1\", \"tag2\", ...]\n"
        "}\n\n"
        "IMPORTANT:\n"
        "1. DO NOT invent or alter any data. If an item is missing, leave it empty. "
        "2. DO NOT skip or merge lines. If the text says \"14. בסיר בינוני...\", you must include that step.\n"
        "3. Return ONLY this JSON object, nothing else.\n\n"
        "Here is the text:\n\n"
        f"{clean_text}\n\n"
        "Now return the JSON with the full recipe, EXACTLY matching the text for ingredients and instructions."
    )
    return prompt

async def fetch_page_with_playwright(url: str) -> str:
    """
    Use Playwright Async API to fetch the webpage.
    """
    logger.debug("Using Async Playwright to fetch the webpage.")
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        await page.goto(url, wait_until="load", timeout=30000)
        content = await page.content()
        await browser.close()
    return content

def extract_text_from_image(image_bytes: bytes) -> str:
    """
    Extract text from an image using Tesseract OCR
    """
    try:
        image = Image.open(io.BytesIO(image_bytes))
        # Perform OCR
        text = pytesseract.image_to_string(image, lang='eng+heb')
        logger.debug(f"Extracted text from image: {len(text)} characters")
        return text
    except Exception as e:
        logger.error(f"Error in OCR processing: {e}")
        raise APIError(f"OCR processing failed: {str(e)}")

def create_image_extraction_prompt(text: str) -> str:
    """
    Create a prompt for the LLM to extract recipe data from OCR text
    """
    prompt = (
        "You are a recipe extraction specialist. Extract recipe details from this OCR-scanned text. "
        "The text may have scanning errors, so use your judgment to interpret it correctly. "
        "Return ONLY a JSON object with the following structure:\n"
        "{\n"
        "  \"title\": \"Recipe title\",\n"
        "  \"description\": \"Brief description\",\n"
        "  \"ingredients\": [\"ingredient 1\", \"ingredient 2\", ...],\n"
        "  \"instructions\": [\"step 1\", \"step 2\", ...],\n"
        "  \"prepTime\": numberOfMinutes,\n"
        "  \"cookTime\": numberOfMinutes,\n"
        "  \"servings\": numberOfServings,\n"
        "  \"tags\": [\"tag1\", \"tag2\", ...]\n"
        "}\n\n"
        "IMPORTANT:\n"
        "1. Return ONLY the JSON object, nothing else\n"
        "2. If you can't determine a value, use a sensible default or empty value\n"
        "3. Keep all steps and ingredients, exactly as they appear\n\n"
        "Here is the scanned text:\n\n"
        f"{text}"
    )
    return prompt

def is_likely_instruction(line: str) -> bool:
    """
    Heuristic filter to decide if a line is a real cooking instruction or irrelevant text.
    """
    # Common cooking/action verbs in Hebrew
    cooking_verbs = [
        "מחממים", "מערבבים", "מוסיפים", "אופים", "מכניסים", "משמנים", "יוצקים",
        "ממיסים", "שמים", "חותכים", "מטגנים", "מרתיחים", "מערבלים", "מקציפים",
        "מקררים", "מצננים", "מתבלים", "מפזרים", "מקלפים", "מגרדים", "מקפלים"
    ]
    normalized = line.lower()

    # If it's obviously referencing other recipes or just "Try also..."
    if "נסו גם את אלו" in normalized:
        return False
    if any(keyword in normalized for keyword in ["סמבוסק", "מניפת פילו", "שבלולי פיצה", "עראיס", "עוגת מייפל"]):
        return False

    # If line is too short, very unlikely to be an instruction
    if len(normalized) < 8:
        return False

    # If it has at least one cooking verb or is fairly long (likely a step)
    if any(verb in normalized for verb in cooking_verbs):
        return True

    # Also allow lines that are somewhat detailed
    if len(normalized) >= 40:
        return True

    return False

def filter_irrelevant_instructions(instructions: List[str]) -> List[str]:
    """
    Filter out lines that are not real cooking steps, e.g. references to other recipes.
    """
    return [inst for inst in instructions if is_likely_instruction(inst)]

def normalize_recipe_fields(recipe_data: dict) -> dict:
    """
    Harmonize field names and unify numeric fields without losing any steps.
    """
    # If there's a "recipeName" but no "title," use recipeName
    if not recipe_data.get("title") and recipe_data.get("recipeName"):
        recipe_data["title"] = recipe_data["recipeName"]

    # Times
    if "prepTime" in recipe_data:
        recipe_data["prepTime"] = parse_time_value(recipe_data["prepTime"])
    elif "prep_time" in recipe_data:
        recipe_data["prepTime"] = parse_time_value(recipe_data["prep_time"])

    if "cookTime" in recipe_data:
        recipe_data["cookTime"] = parse_time_value(recipe_data["cookTime"])
    elif "cook_time" in recipe_data:
        recipe_data["cookTime"] = parse_time_value(recipe_data["cook_time"])

    # Servings
    if "servings" in recipe_data:
        recipe_data["servings"] = parse_servings(recipe_data["servings"])
    elif "recipeYield" in recipe_data:
        recipe_data["servings"] = parse_servings(recipe_data["recipeYield"])

    # Ingredients
    if "ingredients" in recipe_data:
        raw_ings = ensure_list(recipe_data["ingredients"])
        normalized_ings = [normalize_ingredient(ing) for ing in raw_ings]
        normalized_ings = extract_unique_lines(normalized_ings)
        # Filter out any potential empty strings *after* normalization
        recipe_data["ingredients"] = [ing for ing in normalized_ings if ing]

    # Instructions
    if "instructions" in recipe_data:
        if isinstance(recipe_data["instructions"], str):
            lines = recipe_data["instructions"].split("\n")
            lines = [clean_html(l) for l in lines if clean_html(l)]
            recipe_data["instructions"] = lines
        else:
            raw_instructions = ensure_list(recipe_data["instructions"])
            final_instructions = []
            for inst in raw_instructions:
                line = clean_html(inst)
                if line:
                    final_instructions.append(line)
            recipe_data["instructions"] = final_instructions

        recipe_data["instructions"] = remove_exact_duplicates(recipe_data["instructions"])
        # Temporarily disable the aggressive instruction filter
        # recipe_data["instructions"] = filter_irrelevant_instructions(recipe_data["instructions"])
        # logger.debug("Instructions filtering DISABLED") # Optional log

    # Tags
    if "tags" in recipe_data:
        if isinstance(recipe_data["tags"], str):
            raw_tags = recipe_data["tags"].split(",")
            final_tags = [clean_html(t) for t in raw_tags if clean_html(t)]
            recipe_data["tags"] = final_tags
        else:
            raw_tags = ensure_list(recipe_data["tags"])
            final_tags = []
            for tag in raw_tags:
                line = clean_html(tag)
                if line:
                    final_tags.append(line)
            recipe_data["tags"] = final_tags

    # Title/description
    if "title" in recipe_data:
        recipe_data["title"] = clean_html(recipe_data["title"])
    if "description" in recipe_data:
        recipe_data["description"] = clean_html(recipe_data["description"])

    # Add default empty lists/values if fields are missing after normalization
    recipe_data.setdefault("title", "")
    recipe_data.setdefault("description", "")
    recipe_data.setdefault("ingredients", [])
    recipe_data.setdefault("instructions", [])
    recipe_data.setdefault("prepTime", 0)
    recipe_data.setdefault("cookTime", 0)
    recipe_data.setdefault("servings", 1)
    recipe_data.setdefault("tags", [])
    recipe_data.setdefault("notes", "")
    recipe_data.setdefault("source", "")
    recipe_data.setdefault("imageUrl", "") # Ensure imageUrl field exists

    return recipe_data

# --- FastAPI app ---
app = FastAPI(
    title="Recipe Keeper API",
    version="1.0.0",
    description="API for extracting recipes from any webpage or image using Ollama"
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Disposition", "Access-Control-Allow-Origin"]
)

@app.exception_handler(APIError)
async def api_error_handler(request, exc: APIError):
    logger.error(f"APIError: {exc.message}", extra={"details": exc.details})
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.message, "details": exc.details, "status_code": exc.status_code}
    )

@app.get("/")
async def root():
    return {
        "message": "Welcome to Recipe Keeper API",
        "docs": "/docs",
        "redoc": "/redoc"
    }

@app.post("/chat")
async def chat(request: ChatRequest):
    """
    Chat endpoint: pass user message to Ollama with optional Hebrew instructions.
    """
    import requests
    try:
        system_prompt = (
            "You are a helpful assistant. Please respond in Hebrew. Your responses should be clear and well-formatted in Hebrew."
            if request.language == "he"
            else "You are a helpful assistant. Please respond in English. Your responses should be well-formatted."
        )
        ollama_req = {
            "model": MODEL_NAME,
            "prompt": f"{system_prompt}\n\nUser: {request.message}\nAssistant:",
            "stream": False
        }
        logger.debug(f"Sending to Ollama: {ollama_req}")
        resp = requests.post(OLLAMA_API_URL, json=ollama_req)
        if resp.status_code != 200:
            raise HTTPException(status_code=500, detail="Ollama request failed")
        data = resp.json()
        return {"response": data.get("response", ""), "model": MODEL_NAME}
    except Exception as e:
        logger.error(f"Error in chat: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/extract_recipe")
async def extract_recipe(request: RecipeExtractionRequest):
    """
    Use Playwright Async API to fetch the full webpage text, pass to the LLM with instructions
    to produce strict JSON containing only the recipe—exactly as found, with no made-up content.
    """
    import requests
    try:
        logger.info(f"Fetching URL: {request.url}")
        try:
            raw_html = await fetch_page_with_playwright(request.url)
        except Exception as e:
            logger.error(f"Playwright fetch failed: {e}", exc_info=True)
            raise HTTPException(status_code=500, detail=f"Failed to fetch page content: {e}")

        if len(raw_html) < 100:
            raise HTTPException(status_code=400, detail="Webpage content too short")

        # Convert HTML to text
        text = extract_recipe_content(raw_html)
        logger.info(f"Text length: {len(text)}")
        logger.debug(f"--- Text sent to LLM ---\n{text[:1000]}...\n--- End Text ---")

        # Build prompt
        prompt = create_recipe_extraction_prompt(text)
        # logger.info(f"Prompt:\n{prompt}") # Optionally disable logging long prompts

        # Send prompt to Ollama (using synchronous requests for now)
        ollama_req = {
            "model": MODEL_NAME,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": 0.3,
                "num_ctx": 4096, # Consider if this needs adjustment based on prompt/text length
                "top_k": 50,
                "top_p": 0.95,
            }
        }
        # Note: requests is synchronous. For a fully async app, consider httpx.
        try:
            resp = requests.post(OLLAMA_API_URL, json=ollama_req, timeout=60)
            resp.raise_for_status()
        except requests.exceptions.RequestException as e:
            logger.error(f"Ollama request failed: {e}", exc_info=True)
            raise HTTPException(status_code=502, detail=f"Failed to contact LLM service: {e}")
            
        data = resp.json()
        output = data.get("response", "")
        logger.info(f"LLM output received (length: {len(output)})")
        logger.debug(f"--- Raw LLM Output ---\n{output}\n--- End Raw LLM Output ---")

        # Extract JSON from the LLM response
        match = re.search(r'\{.*\}', output, re.DOTALL)
        if not match:
            logger.error(f"No JSON found in LLM output: {output[:500]}...") # Log beginning of output
            raise HTTPException(status_code=500, detail="No valid JSON structure found in LLM response")

        json_str = match.group()
        try:
            recipe_dict = json.loads(json_str)
            logger.debug(f"Raw LLM JSON parsed: {recipe_dict}") # Log the parsed dict
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON from LLM: {e}. JSON String: {json_str[:500]}...", exc_info=True)
            raise HTTPException(status_code=500, detail=f"Invalid JSON format received from LLM: {e}")

        # Normalize fields (ensuring no None->strip errors, removing irrelevant instructions)
        try:
            logger.debug(f"Recipe dict BEFORE normalization: {recipe_dict}")
            recipe_dict = normalize_recipe_fields(recipe_dict)
            logger.debug(f"Recipe dict AFTER normalization: {recipe_dict}")
        except Exception as e:
             logger.error(f"Error normalizing recipe fields: {e}", exc_info=True)
             # Don't fail the whole request, just return the raw dict maybe?
             # Or raise specific normalization error
             pass # Continue with potentially unnormalized data for now

        logger.info(f"Extracted recipe: {recipe_dict.get('title', 'No title')}")
        return recipe_dict

    except HTTPException: # Re-raise HTTPExceptions
        raise
    except Exception as e: # Catch other unexpected errors
        logger.error(f"Unexpected recipe extraction error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="An unexpected error occurred during recipe extraction")

@app.post("/extract_recipe_from_image")
async def extract_recipe_from_image(request: ImageExtractionRequest):
    """
    Extract recipe from an uploaded image using OCR and LLM
    """
    import requests
    try:
        # Decode base64 image
        try:
            image_data = base64.b64decode(request.image_data.split(',')[1] if ',' in request.image_data else request.image_data)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Invalid image data: {str(e)}")
        
        # Extract text using OCR
        text = extract_text_from_image(image_data)
        if not text or len(text) < 50:
            raise HTTPException(status_code=400, detail="Not enough text extracted from image")
        
        logger.info(f"Extracted text from image: {len(text)} characters")
        
        # Create prompt for LLM
        prompt = create_image_extraction_prompt(text)
        
        # Send to Ollama
        ollama_req = {
            "model": MODEL_NAME,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": 0.3,
                "num_ctx": 4096,
                "top_k": 50,
                "top_p": 0.95,
            }
        }
        
        resp = requests.post(OLLAMA_API_URL, json=ollama_req, timeout=60)
        resp.raise_for_status()
        data = resp.json()
        output = data.get("response", "")
        
        # Extract JSON from response
        match = re.search(r'\{.*\}', output, re.DOTALL)
        if not match:
            raise HTTPException(status_code=500, detail="No JSON found in LLM output")
            
        json_str = match.group()
        try:
            recipe_dict = json.loads(json_str)
        except json.JSONDecodeError:
            raise HTTPException(status_code=500, detail="Invalid JSON from LLM")
            
        # Normalize and clean up fields (remove irrelevant lines)
        recipe_dict = normalize_recipe_fields(recipe_dict)
        
        logger.info(f"Extracted recipe from image: {recipe_dict.get('title', 'No title')}")
        return recipe_dict
        
    except Exception as e:
        logger.error(f"Image recipe extraction error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error processing image: {str(e)}")

@app.post("/upload_recipe_image")
async def upload_recipe_image(file: UploadFile = File(...)):
    """
    Upload and process a recipe image
    """
    try:
        # Read the image
        contents = await file.read()
        
        # Extract text using OCR
        text = extract_text_from_image(contents)
        if not text or len(text) < 50:
            raise HTTPException(status_code=400, detail="Not enough text extracted from image")
        
        # Create prompt for LLM
        prompt = create_image_extraction_prompt(text)
        
        # Send to Ollama
        import requests
        ollama_req = {
            "model": MODEL_NAME,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": 0.3,
                "num_ctx": 4096,
                "top_k": 50,
                "top_p": 0.95,
            }
        }
        
        resp = requests.post(OLLAMA_API_URL, json=ollama_req, timeout=60)
        resp.raise_for_status()
        data = resp.json()
        output = data.get("response", "")
        
        # Extract JSON from response
        match = re.search(r'\{.*\}', output, re.DOTALL)
        if not match:
            raise HTTPException(status_code=500, detail="No JSON found in LLM output")
            
        json_str = match.group()
        try:
            recipe_dict = json.loads(json_str)
        except json.JSONDecodeError:
            raise HTTPException(status_code=500, detail="Invalid JSON from LLM")
            
        # Normalize and clean up fields (remove irrelevant lines)
        recipe_dict = normalize_recipe_fields(recipe_dict)
        
        logger.info(f"Extracted recipe from uploaded image: {recipe_dict.get('title', 'No title')}")
        return recipe_dict
        
    except Exception as e:
        logger.error(f"Error processing uploaded image: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error processing uploaded image: {str(e)}")

# New route for custom recipe generation
@app.post("/custom_recipe")
async def custom_recipe(request: CustomRecipeRequest):
    """
    Generate a custom recipe based on provided groceries and a general description.
    """
    import requests
    try:
        # Build a prompt for recipe generation
        prompt = (
            "You are a recipe creation expert. Based on the following groceries and request, "
            "create a detailed recipe. Include title, description, ingredients, instructions, prepTime, cookTime, servings, and tags. "
            "Do not invent any details beyond what is reasonable given the inputs.\n\n"
            "Groceries: " + request.groceries + "\n\n" +
            "Request: " + request.description + "\n\n" +
            "Return the recipe in a strict JSON format with the following keys:\n"
            "{\n"
            "  \"title\": \"Recipe title\",\n"
            "  \"description\": \"Brief description\",\n"
            "  \"ingredients\": [\"ingredient 1\", \"ingredient 2\", ...],\n"
            "  \"instructions\": [\"step 1\", \"step 2\", ...],\n"
            "  \"prepTime\": numberOfMinutes,\n"
            "  \"cookTime\": numberOfMinutes,\n"
            "  \"servings\": numberOfServings,\n"
            "  \"tags\": [\"tag1\", \"tag2\", ...]\n"
            "}\n\n"
            "Ensure the recipe is consistent and realistic. Return ONLY the JSON."
        )
        ollama_req = {
            "model": MODEL_NAME,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": 0.5,
                "num_ctx": 4096,
                "top_k": 50,
                "top_p": 0.95,
            }
        }
        resp = requests.post(OLLAMA_API_URL, json=ollama_req, timeout=60)
        resp.raise_for_status()
        data = resp.json()
        output = data.get("response", "")
        # Extract JSON from the output
        match = re.search(r'\{.*\}', output, re.DOTALL)
        if not match:
            raise HTTPException(status_code=500, detail="No valid JSON structure found in LLM response")
        json_str = match.group()
        try:
            recipe_dict = json.loads(json_str)
        except json.JSONDecodeError as e:
            raise HTTPException(status_code=500, detail=f"Invalid JSON format received from LLM: {e}")
        # Normalize fields (using existing normalization functions)
        recipe_dict = normalize_recipe_fields(recipe_dict)
        return recipe_dict
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error generating custom recipe: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="An unexpected error occurred during custom recipe generation")

# Add a route for proxying images to bypass CORS restrictions
@app.get("/proxy_image")
async def proxy_image(url: str):
    """
    Proxy an image from an external URL to bypass CORS restrictions.
    """
    import requests
    from fastapi.responses import Response
    
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        
        # Get the content type
        content_type = response.headers.get("Content-Type", "image/jpeg")
        
        # Return the image with the proper content type
        return Response(
            content=response.content, 
            media_type=content_type,
            headers={
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "public, max-age=86400"  # Cache for 24 hours
            }
        )
    except Exception as e:
        logger.error(f"Error proxying image: {e}")
        raise APIError(f"Failed to proxy image: {str(e)}", status_code=500)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
