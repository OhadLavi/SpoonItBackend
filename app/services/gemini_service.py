""""Gemini LLM service for recipe extraction and generation."""

import asyncio
import json
import logging
from typing import Any, Dict, List, Tuple

from google import genai
from google.genai import types

from app.config import settings
from app.models.recipe import Recipe
from app.utils.exceptions import GeminiError
from app.utils.gemini_helpers import get_clean_recipe_schema
from app.utils.recipe_normalization import normalize_recipe_data

logger = logging.getLogger(__name__)

try:
    from PIL import Image, ImageEnhance, ImageOps  # type: ignore
    from io import BytesIO
    _PIL_AVAILABLE = True
except Exception:
    _PIL_AVAILABLE = False

try:
    import pytesseract
    _TESSERACT_AVAILABLE = True
except ImportError:
    _TESSERACT_AVAILABLE = False
    logger.warning("pytesseract not available. OCR functionality will be disabled.")


class GeminiService:
    """Service for interacting with Gemini API."""

    def __init__(self):
        self._client = None

    @property
    def client(self):
        if self._client is None:
            self._client = genai.Client(api_key=settings.gemini_api_key)
        return self._client

    # --------------------------
    # Public API
    # --------------------------

    async def extract_recipe_from_image(self, image_data: bytes, mime_type: str) -> Recipe:
        """
        Extract recipe from image using OCR + Gemini:
        (1) Extract text from image using OCR (Tesseract)
        (2) Structure the extracted text into Recipe JSON using Gemini
        """
        try:
            logger.info(f"Extracting recipe from image (mime_type: {mime_type})")

            # Preprocess image for better OCR results
            processed_bytes, processed_mime = self._preprocess_image_for_handwriting(image_data, mime_type)
            
            # Extract text using OCR
            extracted_text = await self._extract_text_with_ocr(processed_bytes)
            
            if not extracted_text or len(extracted_text.strip()) < 10:
                raise GeminiError("OCR failed to extract any meaningful text from the image")

            logger.info(f"OCR extracted {len(extracted_text)} characters of text")
            logger.debug(f"OCR extracted text preview: {extracted_text[:500]}")

            # Structure the extracted text into Recipe JSON using Gemini
            recipe_json = await self._structure_recipe_from_text(extracted_text)

            normalized = normalize_recipe_data(recipe_json)
            return Recipe(**normalized)

        except Exception as e:
            logger.error(f"Image extraction failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to extract recipe from image: {str(e)}") from e

    async def generate_recipe_from_ingredients(self, ingredients: List[str]) -> Recipe:
        prompt = self._build_generation_prompt(ingredients)
        try:
            schema = get_clean_recipe_schema()
            config = types.GenerateContentConfig(
                temperature=settings.gemini_temperature,
                response_mime_type="application/json",
                response_schema=schema,
            )
            
            logger.info(
                "Sending to Gemini (generate_recipe_from_ingredients)",
                extra={
                    "model": settings.gemini_model,
                    "ingredients_count": len(ingredients),
                },
            )
            logger.debug(f"  Prompt: {prompt}")
            logger.debug(
                "  Config / schema",
                extra={
                    "temperature": config.temperature,
                    "response_mime_type": config.response_mime_type,
                },
            )
            
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                None,
                lambda: self.client.models.generate_content(
                    model=settings.gemini_model,
                    contents=prompt,
                    config=config,
                ),
            )
            if response is None or response.text is None or not response.text.strip():
                raise GeminiError("Gemini returned empty response for recipe generation")

            recipe_json = json.loads(response.text)
            normalized = normalize_recipe_data(recipe_json)
            return Recipe(**normalized)

        except Exception as e:
            logger.error(f"Recipe generation failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to generate recipe: {str(e)}") from e

    async def generate_recipe_from_text(self, user_prompt: str) -> Recipe:
        prompt = self._build_text_generation_prompt(user_prompt)
        try:
            schema = get_clean_recipe_schema()
            config = types.GenerateContentConfig(
                temperature=settings.gemini_temperature,
                response_mime_type="application/json",
                response_schema=schema,
            )
            
            logger.info(
                "Sending to Gemini (generate_recipe_from_text)",
                extra={
                    "model": settings.gemini_model,
                },
            )
            logger.debug(f"  Prompt: {prompt}")
            logger.debug(
                "  Config / schema",
                extra={
                    "temperature": config.temperature,
                    "response_mime_type": config.response_mime_type,
                },
            )
            
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                None,
                lambda: self.client.models.generate_content(
                    model=settings.gemini_model,
                    contents=prompt,
                    config=config,
                ),
            )
            if response is None or response.text is None or not response.text.strip():
                raise GeminiError("Gemini returned empty response for text generation")

            recipe_json = json.loads(response.text)
            normalized = normalize_recipe_data(recipe_json)
            return Recipe(**normalized)

        except Exception as e:
            logger.error(f"Text recipe generation failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to generate recipe from text: {str(e)}") from e

    # --------------------------
    # OCR Text Extraction
    # --------------------------

    async def _extract_text_with_ocr(self, image_bytes: bytes) -> str:
        """
        Extract text from image using Tesseract OCR.
        Returns the raw extracted text.
        """
        if not _TESSERACT_AVAILABLE:
            raise GeminiError("Tesseract OCR is not available. Please install pytesseract and Tesseract.")
        
        if not _PIL_AVAILABLE:
            raise GeminiError("PIL/Pillow is not available for image processing.")
        
        try:
            # Open image with PIL
            image = Image.open(BytesIO(image_bytes))
            
            # Run OCR with Hebrew and English languages
            # Tesseract language codes: 'heb' for Hebrew, 'eng' for English
            loop = asyncio.get_running_loop()
            extracted_text = await loop.run_in_executor(
                None,
                lambda: pytesseract.image_to_string(
                    image,
                    lang='heb+eng',  # Hebrew + English
                    config='--psm 6'  # Assume a single uniform block of text
                )
            )
            
            return extracted_text.strip()
            
        except pytesseract.TesseractNotFoundError:
            raise GeminiError("Tesseract OCR engine not found. Please install Tesseract OCR on your system.")
        except Exception as e:
            logger.error(f"OCR extraction failed: {e}", exc_info=True)
            raise GeminiError(f"Failed to extract text from image using OCR: {str(e)}") from e

    async def _structure_recipe_from_text(self, extracted_text: str) -> Dict[str, Any]:
        """
        Convert OCR-extracted text -> Recipe JSON using Gemini.
        """
        prompt = f"""
יש לך טקסט שמופיע במתכון מתוך תמונה (הוצא באמצעות OCR).
אתה חייב לבנות אובייקט Recipe JSON תקין *בדיוק לפי הסכימה*.
אסור להוסיף שום מרכיב/שלב שלא קיים בטקסט.

טקסט שהוצא מהתמונה:
{extracted_text}

כללים:
- ingredientGroups: כל מרכיב חייב להיות עם raw זהה לשורה המקורית.
- instructionGroups.instructions חייב להיות List[str] של צעדים (לא פסקה אחת).
- אם יש הערת סוגריים (למשל "(...)") — זה לא צעד; זה הערה.
- אם יש שורה עם ":" (למשל "קרם: ...") — זה תחילת סעיף/קבוצה להוראות בשם "קרם".
- nutrition: אם לא בטוח, מלא 0 (לא null) ו-per="מנה".

החזר JSON בלבד.
""".strip()

        schema = get_clean_recipe_schema()
        config = types.GenerateContentConfig(
            temperature=0.0,
            response_mime_type="application/json",
            response_schema=schema,
        )
        
        logger.info(
            "Sending to Gemini (_structure_recipe_from_text)",
            extra={
                "model": settings.gemini_model,
            },
        )
        logger.debug(f"  Prompt: {prompt}")
        logger.debug(
            "  Config / schema",
            extra={
                "temperature": config.temperature,
                "response_mime_type": config.response_mime_type,
            },
        )
        
        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None,
            lambda: self.client.models.generate_content(
                model=settings.gemini_model,
                contents=prompt,
                config=config,
            ),
        )

        if response is None or response.text is None or not response.text.strip():
            raise GeminiError("Gemini returned empty response for structuring from OCR text")

        raw = response.text.strip()
        logger.info(f"Gemini structured-from-OCR-text raw:\n{raw}")

        return json.loads(raw)

    # --------------------------
    # Prompts for generation
    # --------------------------

    def _build_generation_prompt(self, ingredients: List[str]) -> str:
        ingredients_text = "\n".join(f"- {ing}" for ing in ingredients)
        return f"""
צור מתכון מקורי עם המרכיבים הבאים:
{ingredients_text}

החזר JSON תקין בלבד לפי מודל Recipe.
- instructionGroups.instructions חייב להיות רשימת צעדים (לא פסקה אחת).
- nutrition חייב להיות אובייקט מלא עם מספרים (אם לא בטוח -> 0).
""".strip()

    def _build_text_generation_prompt(self, user_prompt: str) -> str:
        return f"""
המשתמש ביקש:
{user_prompt}

צור מתכון מתאים לבקשה והחזר JSON תקין בלבד לפי מודל Recipe.
- instructionGroups.instructions חייב להיות רשימת צעדים (לא פסקה אחת).
- nutrition חייב להיות אובייקט מלא עם מספרים (אם לא בטוח -> 0).
""".strip()

    # --------------------------
    # Image preprocessing
    # --------------------------

    def _preprocess_image_for_handwriting(self, image_bytes: bytes, mime_type: str) -> Tuple[bytes, str]:
        """
        Improve handwriting readability:
          - exif transpose
          - grayscale
          - autocontrast
          - stronger contrast/sharpness
          - resize up to a higher max_dim to avoid losing small words
        """
        if not _PIL_AVAILABLE:
            return image_bytes, mime_type

        try:
            img = Image.open(BytesIO(image_bytes))
            img = ImageOps.exif_transpose(img)

            img = img.convert("L")
            img = ImageOps.autocontrast(img, cutoff=1)

            img = ImageEnhance.Contrast(img).enhance(1.55)
            img = ImageEnhance.Sharpness(img).enhance(1.35)

            # Keep more resolution to catch small words like "על הגז"
            max_dim = 2400
            w, h = img.size
            scale = min(1.0, max_dim / max(w, h))
            if scale < 1.0:
                img = img.resize((int(w * scale), int(h * scale)))

            out = BytesIO()
            img.save(out, format="PNG", optimize=True)
            return out.getvalue(), "image/png"

        except Exception as e:
            logger.warning(f"Image preprocess failed, using original: {e}")
            return image_bytes, mime_type
