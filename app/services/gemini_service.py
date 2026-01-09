""""Gemini LLM service for recipe extraction and generation."""

import asyncio
import base64
import json
import logging
import re
from typing import Any, Dict, List, Optional, Tuple

from google import genai
from google.genai import types

from app.config import settings
from app.models.recipe import Recipe
from app.utils.exceptions import GeminiError

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

    def _clean_schema_for_gemini(self, schema: Dict[str, Any]) -> Dict[str, Any]:
        """
        Remove fields that Gemini API doesn't accept in response_schema.
        Specifically removes 'additionalProperties' and 'additional_properties'.
        """
        if not isinstance(schema, dict):
            return schema
        
        cleaned = {}
        for key, value in schema.items():
            # Skip additionalProperties fields
            if key in ("additionalProperties", "additional_properties"):
                continue
            
            # Recursively clean nested dictionaries
            if isinstance(value, dict):
                cleaned[key] = self._clean_schema_for_gemini(value)
            elif isinstance(value, list):
                cleaned[key] = [
                    self._clean_schema_for_gemini(item) if isinstance(item, dict) else item
                    for item in value
                ]
            else:
                cleaned[key] = value
        
        return cleaned

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

            normalized = self._normalize_recipe_json(recipe_json)
            return Recipe(**normalized)

        except Exception as e:
            logger.error(f"Image extraction failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to extract recipe from image: {str(e)}") from e

    async def generate_recipe_from_ingredients(self, ingredients: List[str]) -> Recipe:
        prompt = self._build_generation_prompt(ingredients)
        try:
            schema = self._clean_schema_for_gemini(Recipe.model_json_schema())
            config = types.GenerateContentConfig(
                temperature=settings.gemini_temperature,
                response_mime_type="application/json",
                response_schema=schema,
            )
            
            logger.info(f"Sending to Gemini (generate_recipe_from_ingredients):")
            logger.info(f"  Model: {settings.gemini_model}")
            logger.info(f"  Prompt: {prompt}")
            logger.info(f"  Config: temperature={config.temperature}, response_mime_type={config.response_mime_type}")
            logger.info(f"  Response schema: {json.dumps(schema, indent=2, ensure_ascii=False)}")
            
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
            normalized = self._normalize_recipe_json(recipe_json)
            return Recipe(**normalized)

        except Exception as e:
            logger.error(f"Recipe generation failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to generate recipe: {str(e)}") from e

    async def generate_recipe_from_text(self, user_prompt: str) -> Recipe:
        prompt = self._build_text_generation_prompt(user_prompt)
        try:
            schema = self._clean_schema_for_gemini(Recipe.model_json_schema())
            config = types.GenerateContentConfig(
                temperature=settings.gemini_temperature,
                response_mime_type="application/json",
                response_schema=schema,
            )
            
            logger.info(f"Sending to Gemini (generate_recipe_from_text):")
            logger.info(f"  Model: {settings.gemini_model}")
            logger.info(f"  Prompt: {prompt}")
            logger.info(f"  Config: temperature={config.temperature}, response_mime_type={config.response_mime_type}")
            logger.info(f"  Response schema: {json.dumps(schema, indent=2, ensure_ascii=False)}")
            
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
            normalized = self._normalize_recipe_json(recipe_json)
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
            extracted_text = pytesseract.image_to_string(
                image,
                lang='heb+eng',  # Hebrew + English
                config='--psm 6'  # Assume a single uniform block of text
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

        schema = self._clean_schema_for_gemini(Recipe.model_json_schema())
        config = types.GenerateContentConfig(
            temperature=0.0,
            response_mime_type="application/json",
            response_schema=schema,
        )
        
        logger.info(f"Sending to Gemini (_structure_recipe_from_text):")
        logger.info(f"  Model: {settings.gemini_model}")
        logger.info(f"  Prompt: {prompt}")
        logger.info(f"  Config: temperature={config.temperature}, response_mime_type={config.response_mime_type}")
        logger.info(f"  Response schema: {json.dumps(schema, indent=2, ensure_ascii=False)}")
        
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
    # Legacy: Pass A: strict transcription (kept for backward compatibility)
    # --------------------------

    async def _transcribe_recipe_text_from_image(self, image_base64: str, mime_type: str) -> Dict[str, Any]:
        """
        Returns JSON with keys only:
          - title (string|null)
          - ingredients_lines (array of strings)
          - instructions_lines (array of strings)
          - other_lines (array of strings)

        IMPORTANT: no guessing. If unreadable -> ??? (do NOT infer).
        """
        prompt = """
תעתיק את כל הטקסט שמופיע בתמונה בצורה מדויקת.

כללים נוקשים:
- אל תתרגם ואל תשפר ניסוח.
- אל תנחש מילים. אם משהו לא קריא כתוב ??? במקום המילה/הקטע.
- אל תשמיט מילים קטנות (כמו: על/בתוך/על הגז/בתנור). תעתיק הכל.
- שמור על סדר השורות כפי שמופיע.
- אל תוסיף שום מידע שלא קיים בתמונה.

החזר JSON בלבד (ללא markdown וללא הסברים) עם המפתחות הבאים בלבד:
- title: string או null
- ingredients_lines: רשימת שורות של מרכיבים (strings)
- instructions_lines: רשימת שורות של הוראות/טקסט הכנה (strings)
- other_lines: כל שורה אחרת שלא בטוח לאיזה חלק שייכת (strings)
""".strip()

        transcript_schema = {
            "type": "object",
            "properties": {
                "title": {"anyOf": [{"type": "string"}, {"type": "null"}]},
                "ingredients_lines": {"type": "array", "items": {"type": "string"}},
                "instructions_lines": {"type": "array", "items": {"type": "string"}},
                "other_lines": {"type": "array", "items": {"type": "string"}},
            },
            "required": ["title", "ingredients_lines", "instructions_lines", "other_lines"],
        }

        loop = asyncio.get_event_loop()
        model_for_ocr = getattr(settings, "gemini_model_ocr", None) or "gemini-2.5-pro"

        config = types.GenerateContentConfig(
            temperature=0.0,
            response_mime_type="application/json",
            response_schema=transcript_schema,
        )
        
        logger.info(f"Sending to Gemini (_transcribe_recipe_text_from_image):")
        logger.info(f"  Model: {model_for_ocr}")
        logger.info(f"  Prompt: {prompt}")
        logger.info(f"  Image: mime_type={mime_type}, data_length={len(image_base64)} chars (base64)")
        logger.info(f"  Config: temperature={config.temperature}, response_mime_type={config.response_mime_type}")
        logger.info(f"  Response schema: {json.dumps(transcript_schema, indent=2, ensure_ascii=False)}")

        response = await loop.run_in_executor(
            None,
            lambda: self.client.models.generate_content(
                model=model_for_ocr,
                contents=[
                    prompt,
                    {"inline_data": {"mime_type": mime_type, "data": image_base64}},
                ],
                config=config,
            ),
        )

        if response is None or response.text is None or not response.text.strip():
            raise GeminiError("Gemini returned empty response for transcription")

        raw = response.text.strip()
        logger.info(f"Gemini transcription raw:\n{raw}")

        data = json.loads(raw)

        return {
            "title": data.get("title"),
            "ingredients_lines": [x for x in (data.get("ingredients_lines") or []) if isinstance(x, str) and x.strip()],
            "instructions_lines": [x for x in (data.get("instructions_lines") or []) if isinstance(x, str) and x.strip()],
            "other_lines": [x for x in (data.get("other_lines") or []) if isinstance(x, str) and x.strip()],
        }

    # --------------------------
    # Pass B: structure only from transcript
    # --------------------------

    async def _structure_recipe_from_transcript(self, transcript: Dict[str, Any]) -> Dict[str, Any]:
        """
        Convert transcript -> Recipe JSON.
        MUST only use provided transcript lines. No invention.
        """
        title = transcript.get("title")
        ingredients_lines = transcript.get("ingredients_lines", [])
        instructions_lines = transcript.get("instructions_lines", [])
        other_lines = transcript.get("other_lines", [])

        prompt = f"""
יש לך תמלול מדויק של מתכון מתוך תמונה.
אתה חייב לבנות אובייקט Recipe JSON תקין *בדיוק לפי הסכימה*.
אסור להוסיף שום מרכיב/שלב שלא קיים בתמלול.

תמלול:
- title: {title}
- ingredients_lines:
{json.dumps(ingredients_lines, ensure_ascii=False)}
- instructions_lines:
{json.dumps(instructions_lines, ensure_ascii=False)}
- other_lines:
{json.dumps(other_lines, ensure_ascii=False)}

כללים:
- ingredientGroups: כל מרכיב חייב להיות עם raw זהה לשורה המקורית.
- instructionGroups.instructions חייב להיות List[str] של צעדים (לא פסקה אחת).
- אם יש הערת סוגריים (למשל "(...)") — זה לא צעד; זה הערה.
- אם יש שורה עם ":" (למשל "קרם: ...") — זה תחילת סעיף/קבוצה להוראות בשם "קרם".
- nutrition: אם לא בטוח, מלא 0 (לא null) ו-per="מנה".

החזר JSON בלבד.
""".strip()

        schema = self._clean_schema_for_gemini(Recipe.model_json_schema())
        config = types.GenerateContentConfig(
            temperature=0.0,
            response_mime_type="application/json",
            response_schema=schema,
        )
        
        logger.info(f"Sending to Gemini (_structure_recipe_from_transcript):")
        logger.info(f"  Model: {settings.gemini_model}")
        logger.info(f"  Prompt: {prompt}")
        logger.info(f"  Config: temperature={config.temperature}, response_mime_type={config.response_mime_type}")
        logger.info(f"  Response schema: {json.dumps(schema, indent=2, ensure_ascii=False)}")
        
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
            raise GeminiError("Gemini returned empty response for structuring from transcript")

        raw = response.text.strip()
        logger.info(f"Gemini structured-from-transcript raw:\n{raw}")

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
    # Normalization + postprocessing
    # --------------------------

    def _normalize_recipe_json(self, recipe_json: Dict[str, Any]) -> Dict[str, Any]:
        """
        Make the output resilient even if Gemini deviates a bit:
        - notes: "" -> []
        - groupName/item schema -> name schema
        - nutrition key variants -> expected keys
        - parentheses lines -> notes
        - "Header:" lines -> new instruction group
        """
        normalized: Dict[str, Any] = dict(recipe_json or {})

        # Map alternate top-level keys if they appear (handle both camelCase and snake_case)
        if "prepTime" in normalized and "prepTimeMinutes" not in normalized and "prep_time_minutes" not in normalized:
            normalized["prepTimeMinutes"] = normalized.pop("prepTime") or None
        if "cookTime" in normalized and "cookTimeMinutes" not in normalized and "cook_time_minutes" not in normalized:
            normalized["cookTimeMinutes"] = normalized.pop("cookTime") or None
        if "totalTime" in normalized and "totalTimeMinutes" not in normalized and "total_time_minutes" not in normalized:
            normalized["totalTimeMinutes"] = normalized.pop("totalTime") or None

        # Ensure list fields exist and have correct types
        normalized["images"] = self._ensure_string_list(normalized.get("images"))
        normalized["notes"] = self._ensure_string_list(normalized.get("notes"))
        normalized.setdefault("ingredientGroups", [])
        normalized.setdefault("instructionGroups", [])

        # servings: normalize to Servings object structure
        if "servings" in normalized:
            servings = normalized["servings"]
            if isinstance(servings, dict):
                # Already a structured object, ensure it has the right fields
                if "amount" not in servings and "unit" not in servings and "raw" not in servings:
                    # Might be old format, try to convert
                    if isinstance(servings.get("value"), (int, float, str)):
                        normalized["servings"] = {
                            "amount": str(servings.get("value")),
                            "unit": servings.get("unit"),
                            "raw": servings.get("raw") or str(servings.get("value", ""))
                        }
            elif isinstance(servings, (int, float)):
                # Convert number to Servings object
                normalized["servings"] = {
                    "amount": str(int(servings)),
                    "unit": None,
                    "raw": str(int(servings))
                }
            elif isinstance(servings, str):
                # String format - try to parse or use as raw
                normalized["servings"] = {
                    "amount": None,
                    "unit": None,
                    "raw": servings
                }
            elif servings is None:
                normalized["servings"] = None
            else:
                # Unknown format, set to None
                normalized["servings"] = None

        # Normalize ingredientGroups schema
        normalized["ingredientGroups"] = self._normalize_ingredient_groups(normalized.get("ingredientGroups"))

        # Normalize instructionGroups schema + apply ":" headers + move "(...)" to notes
        notes_list = normalized["notes"]
        normalized["instructionGroups"] = self._normalize_instruction_groups_with_rules(
            normalized.get("instructionGroups"),
            notes_list=notes_list,
        )
        normalized["notes"] = notes_list

        # Ensure nutrition is never null + normalize key variants
        normalized["nutrition"] = self._ensure_nutrition_object(normalized.get("nutrition"))

        # Compute total time if missing and parts exist (handle both camelCase and snake_case)
        total_time = normalized.get("totalTimeMinutes") or normalized.get("total_time_minutes")
        if total_time is None:
            prep_time = normalized.get("prepTimeMinutes") or normalized.get("prep_time_minutes") or 0
            cook_time = normalized.get("cookTimeMinutes") or normalized.get("cook_time_minutes") or 0
            if isinstance(prep_time, (int, float)) and isinstance(cook_time, (int, float)) and (prep_time or cook_time):
                normalized["totalTimeMinutes"] = int(prep_time + cook_time)

        # Remove ingredients field (it's computed, not stored)
        normalized.pop("ingredients", None)

        return normalized

    def _ensure_string_list(self, v: Any) -> List[str]:
        if v is None:
            return []
        if isinstance(v, list):
            return [str(x).strip() for x in v if isinstance(x, (str, int, float)) and str(x).strip()]
        if isinstance(v, str):
            s = v.strip()
            return [s] if s else []
        # fallback
        s = str(v).strip()
        return [s] if s else []

    def _normalize_ingredient_groups(self, groups: Any) -> List[Dict[str, Any]]:
        if not isinstance(groups, list):
            return []

        out: List[Dict[str, Any]] = []
        for g in groups:
            if not isinstance(g, dict):
                continue

            # accept both name/groupName
            name = g.get("name")
            if name is None:
                name = g.get("groupName")
            if name is not None and not isinstance(name, str):
                name = str(name)

            ingr = g.get("ingredients", [])
            normalized_ingredients: List[Dict[str, Any]] = []

            if isinstance(ingr, list):
                for ing in ingr:
                    if isinstance(ing, str):
                        normalized_ingredients.append(
                            {
                                "name": ing,
                                "amount": None,
                                "preparation": None,
                                "raw": ing,
                            }
                        )
                        continue

                    if not isinstance(ing, dict):
                        normalized_ingredients.append({"name": str(ing), "amount": None, "preparation": None, "raw": str(ing)})
                        continue

                    raw = ing.get("raw")
                    if raw is not None and not isinstance(raw, str):
                        raw = str(raw)

                    # accept item/name
                    ing_name = ing.get("name")
                    if ing_name is None:
                        ing_name = ing.get("item")
                    if ing_name is None:
                        ing_name = raw or ""
                    if ing_name is not None and not isinstance(ing_name, str):
                        ing_name = str(ing_name)

                    # Handle amount: combine quantity + unit, or use existing amount
                    amount = ing.get("amount")
                    if amount is None:
                        # Try to combine quantity + unit from old format
                        qty = ing.get("quantity")
                        unit = ing.get("unit")
                        if qty or unit:
                            parts = []
                            if qty:
                                parts.append(str(qty))
                            if unit:
                                parts.append(str(unit))
                            amount = " ".join(parts) if parts else None
                    
                    if amount is not None and not isinstance(amount, str):
                        amount = str(amount)
                    if amount == "":
                        amount = None

                    # ingredient notes -> preparation (best fit in your schema)
                    prep = ing.get("preparation")
                    if prep is None:
                        prep = ing.get("notes")
                    if prep is not None and not isinstance(prep, str):
                        prep = str(prep)

                    normalized_ingredients.append(
                        {
                            "name": ing_name or "",
                            "amount": amount,
                            "preparation": prep,
                            "raw": raw or (ing.get("raw") if isinstance(ing.get("raw"), str) else None) or (ing_name or ""),
                        }
                    )

            out.append({"name": name, "ingredients": normalized_ingredients})

        return out

    def _normalize_instruction_groups_with_rules(self, groups: Any, notes_list: List[str]) -> List[Dict[str, Any]]:
        if not isinstance(groups, list):
            groups = []

        # First: coerce to (name, steps list[str])
        flattened: List[Tuple[str, List[str]]] = []
        for g in groups:
            if not isinstance(g, dict):
                continue

            name = g.get("name") or g.get("groupName") or "הוראות"
            if not isinstance(name, str):
                name = str(name)

            instr = g.get("instructions")
            steps: List[str] = []

            if isinstance(instr, str):
                steps = self._split_to_steps(instr, aggressive=True)
            elif isinstance(instr, list):
                for item in instr:
                    if isinstance(item, str):
                        steps.extend(self._split_to_steps(item, aggressive=False))

            steps = [self._strip_bullets(s) for s in steps if isinstance(s, str) and s.strip()]
            flattened.append((name, steps))

        # If empty, ensure at least one group
        if not flattened:
            flattened = [("הוראות", [])]

        # Apply rules:
        # - "(...)" => note
        # - "קרם: ..." => new group "קרם"
        out_groups: List[Dict[str, Any]] = []
        for base_name, steps in flattened:
            refined = self._refine_steps_into_groups(base_name, steps, notes_list)
            out_groups.extend(refined)

        # Drop empty groups (unless everything empty)
        out_groups = [g for g in out_groups if g.get("instructions")]
        if not out_groups:
            out_groups = [{"name": "הוראות", "instructions": []}]

        return out_groups

    def _refine_steps_into_groups(self, initial_group_name: str, steps: List[str], notes_list: List[str]) -> List[Dict[str, Any]]:
        groups: List[Dict[str, Any]] = [{"name": initial_group_name or "הוראות", "instructions": []}]
        current = groups[-1]

        header_re = re.compile(r"^([^:]{1,24}):\s*(.*)$")  # header max length to avoid false positives

        for s in steps:
            t = s.strip()
            if not t:
                continue

            # Parentheses note => notes (NOT a step)
            if self._is_parenthetical_note(t):
                note = self._strip_outer_parens(t).strip()
                if note:
                    notes_list.append(note)
                continue

            m = header_re.match(t)
            if m:
                header = m.group(1).strip()
                rest = (m.group(2) or "").strip()

                # Start new instruction group
                current = {"name": header, "instructions": []}
                groups.append(current)

                if rest:
                    current["instructions"].append(rest)
                continue

            current["instructions"].append(t)

        # Remove empty initial group if it stayed empty and there are other groups
        if len(groups) > 1 and not groups[0]["instructions"]:
            groups = groups[1:]

        return groups

    def _strip_bullets(self, s: str) -> str:
        return re.sub(r"^\s*[\*\-\u2022]\s*", "", s).strip()

    def _is_parenthetical_note(self, s: str) -> bool:
        t = s.strip()
        return t.startswith("(") and t.endswith(")") and len(t) >= 3

    def _strip_outer_parens(self, s: str) -> str:
        t = s.strip()
        if self._is_parenthetical_note(t):
            return t[1:-1]
        return t

    def _split_to_steps(self, text: str, aggressive: bool = False) -> List[str]:
        """
        Split into steps WITHOUT verb lists.
        Uses punctuation + separators + sequencing words.
        """
        t = (text or "").strip()
        if not t:
            return []

        t = re.sub(r"\s+", " ", t)

        if aggressive:
            t = re.sub(r"\s+(ואז|אחר כך|לאחר מכן)\s+", r" | \1 ", t)

        # Split by sentence punctuation
        parts = re.split(r"(?<=[\.\!\?])\s+", t)

        expanded: List[str] = []
        for p in parts:
            p = p.strip()
            if not p:
                continue
            for sep in ["\n", ";", " - ", " – ", " — "]:
                if sep in p:
                    chunks = [c.strip() for c in p.split(sep) if c.strip()]
                    p = " | ".join(chunks)
            expanded.extend([x.strip() for x in p.split("|") if x.strip()])

        # Comma split only if likely multi-step
        final_steps: List[str] = []
        for p in expanded:
            p = p.strip()
            if not p:
                continue

            if "," in p and (aggressive or self._likely_multi_step_clause(p)):
                chunks = [c.strip() for c in p.split(",") if c.strip()]
                merged: List[str] = []
                for c in chunks:
                    if merged and len(c) < 6:
                        merged[-1] = f"{merged[-1]}, {c}"
                    else:
                        merged.append(c)
                final_steps.extend(merged)
            else:
                final_steps.append(p)

        return [re.sub(r"\s+", " ", s).strip() for s in final_steps if s.strip()]

    def _likely_multi_step_clause(self, s: str) -> bool:
        if s.count(",") >= 2:
            return True

        time_hits = len(re.findall(r"\b\d+\s*(דק|דק'|דקות|שעה|שעות)\b", s))
        temp_hits = len(re.findall(r"\b\d+\s*(מעלות|°)\b", s))
        if time_hits + temp_hits >= 2:
            return True

        if " ואז " in s or " אחר כך " in s or " לאחר מכן " in s:
            return True

        return False

    def _ensure_nutrition_object(self, nutrition: Any) -> Optional[Dict[str, Any]]:
        """
        Normalize nutrition to your schema:
          calories, protein_g, fat_g, carbs_g, per
        Accepts variants like protein/carbohydrates/fat.
        Only returns allowed fields (filters out extra fields like saturated_fat, sugar, etc.)
        """
        def _f(x: Any) -> Optional[float]:
            if x is None:
                return None
            if isinstance(x, str):
                try:
                    cleaned = ''.join(c for c in x if c.isdigit() or c == '.')
                    return float(cleaned) if cleaned else None
                except (ValueError, TypeError):
                    return None
            try:
                val = float(x)
                return val if val >= 0 else None
            except (ValueError, TypeError):
                return None

        if not isinstance(nutrition, dict):
            return None

        # Only extract and return allowed fields
        normalized = {}
        
        # calories
        normalized["calories"] = _f(nutrition.get("calories"))
        
        # protein_g (map from protein or protein_g)
        normalized["protein_g"] = _f(nutrition.get("protein_g") or nutrition.get("protein"))
        
        # fat_g (map from fat or fat_g)
        normalized["fat_g"] = _f(nutrition.get("fat_g") or nutrition.get("fat"))
        
        # carbs_g (map from carbs, carbohydrates, or carbs_g)
        normalized["carbs_g"] = _f(nutrition.get("carbs_g") or nutrition.get("carbs") or nutrition.get("carbohydrates"))
        
        # per
        per = nutrition.get("per")
        normalized["per"] = per if isinstance(per, str) else "מנה"
        
        # Return None if all values are None (instead of empty dict)
        if all(v is None for k, v in normalized.items() if k != "per"):
            return None
        
        return normalized

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
