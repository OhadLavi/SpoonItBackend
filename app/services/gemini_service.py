"""
Gemini LLM service for recipe extraction and generation.

Key design:
- Image extraction = OCR-faithful (do NOT interpret quantities/units). We keep the ingredient line as-is.
- Nutrition for image extraction = null (no guessing). Do nutrition/enrichment in a separate step.
- Strict JSON guard + automatic repair retries if Gemini returns invalid JSON / wrong schema.
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import re
from typing import Any, Dict, List, Optional

from google import genai
from google.genai import types
from pydantic import ValidationError

from app.config import settings
from app.models.recipe import Recipe
from app.utils.exceptions import GeminiError

logger = logging.getLogger(__name__)


# ----------------------------
# Models (override via settings if you want)
# ----------------------------
DEFAULT_IMAGE_MODEL = getattr(settings, "gemini_image_model", None) or "gemini-2.5-pro"
DEFAULT_TEXT_MODEL = getattr(settings, "gemini_text_model", None) or "gemini-2.5-flash"


class GeminiService:
    """Service for interacting with Gemini API."""

    def __init__(self) -> None:
        self._client: Optional[genai.Client] = None

    @property
    def client(self) -> genai.Client:
        """Get or create Gemini client (lazy initialization)."""
        if self._client is None:
            self._client = genai.Client(api_key=settings.gemini_api_key)
        return self._client

    # ---------------------------------------------------------------------
    # Public API
    # ---------------------------------------------------------------------

    async def extract_recipe_from_image(self, image_data: bytes, mime_type: str) -> Recipe:
        """
        Extract recipe from image using Gemini Vision (OCR-faithful).

        IMPORTANT behavior:
        - Ingredients are preserved as-is (raw line), no quantity/unit parsing.
        - Nutrition is null (no guessing).
        """
        prompt = self._build_image_extraction_prompt()

        # Inline image data
        image_base64 = base64.b64encode(image_data).decode("utf-8")
        contents = [
            prompt,
            {"inline_data": {"mime_type": mime_type, "data": image_base64}},
        ]

        try:
            logger.info("Extracting recipe from image (mime_type=%s)", mime_type)

            recipe_json = await self._generate_json_with_retries(
                model=DEFAULT_IMAGE_MODEL,
                contents=contents,
                schema=Recipe.model_json_schema(),
                temperature=0.0,
                max_retries=2,
            )

            normalized = self._normalize_recipe_json(recipe_json, ocr_mode=True)
            return Recipe(**normalized)

        except (json.JSONDecodeError, ValidationError) as e:
            logger.error("Image extraction parse/validation failed: %s", str(e), exc_info=True)
            raise GeminiError(f"Failed to parse/validate recipe JSON from image: {str(e)}") from e
        except Exception as e:
            logger.error("Image extraction failed: %s", str(e), exc_info=True)
            raise GeminiError(f"Failed to extract recipe from image: {str(e)}") from e

    async def generate_recipe_from_ingredients(self, ingredients: List[str]) -> Recipe:
        """
        Generate a recipe from a list of ingredients (creative generation).
        Here, nutrition can be estimated (you asked for it previously).
        """
        prompt = self._build_generation_prompt(ingredients)

        try:
            logger.info("Generating recipe from %d ingredients", len(ingredients))

            recipe_json = await self._generate_json_with_retries(
                model=DEFAULT_TEXT_MODEL,
                contents=prompt,
                schema=Recipe.model_json_schema(),
                temperature=0.2,
                max_retries=2,
            )

            normalized = self._normalize_recipe_json(recipe_json, ocr_mode=False)
            return Recipe(**normalized)

        except (json.JSONDecodeError, ValidationError) as e:
            logger.error("Recipe generation parse/validation failed: %s", str(e), exc_info=True)
            raise GeminiError(f"Failed to parse/validate generated recipe JSON: {str(e)}") from e
        except Exception as e:
            logger.error("Recipe generation failed: %s", str(e), exc_info=True)
            raise GeminiError(f"Failed to generate recipe: {str(e)}") from e

    async def generate_recipe_from_text(self, user_prompt: str) -> Recipe:
        """
        Generate a recipe from free-form text (chat-based).
        """
        prompt = self._build_text_generation_prompt(user_prompt)

        try:
            logger.info("Generating recipe from text prompt")

            recipe_json = await self._generate_json_with_retries(
                model=DEFAULT_TEXT_MODEL,
                contents=prompt,
                schema=Recipe.model_json_schema(),
                temperature=0.2,
                max_retries=2,
            )

            normalized = self._normalize_recipe_json(recipe_json, ocr_mode=False)
            return Recipe(**normalized)

        except (json.JSONDecodeError, ValidationError) as e:
            logger.error("Text recipe generation parse/validation failed: %s", str(e), exc_info=True)
            raise GeminiError(f"Failed to parse/validate generated recipe JSON: {str(e)}") from e
        except Exception as e:
            logger.error("Text recipe generation failed: %s", str(e), exc_info=True)
            raise GeminiError(f"Failed to generate recipe from text: {str(e)}") from e

    async def enrich_nutrition(self, recipe: Recipe) -> Recipe:
        """
        Optional step (recommended): compute/estimate nutrition AFTER OCR extraction.

        This avoids hallucinated nutrition during image extraction.
        """
        prompt = self._build_nutrition_enrichment_prompt(recipe)

        try:
            logger.info("Enriching nutrition for recipe title=%s", recipe.title)

            recipe_json = await self._generate_json_with_retries(
                model=DEFAULT_TEXT_MODEL,
                contents=prompt,
                schema=Recipe.model_json_schema(),
                temperature=0.0,
                max_retries=2,
            )

            normalized = self._normalize_recipe_json(recipe_json, ocr_mode=False)
            return Recipe(**normalized)

        except Exception as e:
            logger.error("Nutrition enrichment failed: %s", str(e), exc_info=True)
            raise GeminiError(f"Failed to enrich nutrition: {str(e)}") from e

    # ---------------------------------------------------------------------
    # Prompts
    # ---------------------------------------------------------------------

    def _build_image_extraction_prompt(self) -> str:
        """
        OCR-faithful prompt: do not interpret quantities/units.
        Keep each ingredient line as a single raw string.
        Nutrition must be null unless explicitly present (usually not).
        """
        return """
חלץ את המתכון מהתמונה.

כללים נוקשים (OCR-faithful):
- החזר JSON תקין בלבד (האובייקט עצמו חייב להתחיל ב-{ ולהסתיים ב-}).
- ללא Markdown, ללא ``` , ללא טקסט לפני/אחרי ה-JSON.
- אל תתרגם ואל תנרמל.
- אל תפצל שברים/מספרים (למשל "3/4 כוס מים" חייב להישאר בדיוק כך).
- אל תפרש כמויות/יחידות. כל מרכיב מוחזר כשורה אחת (raw).
- אל תמציא מרכיבים/שלבים/זמנים שלא מופיעים בתמונה.
- אם שדה לא מופיע בתמונה: השתמש null לשדות, [] לרשימות.

מבנה מרכיבים:
- ingredientGroups[*].ingredients[*] חייבים להיות אובייקטים עם:
  - raw: הטקסט המדויק של המרכיב כפי שמופיע בתמונה
  - name: אותו ערך כמו raw (כדי להתאים לסכמות), ללא פירוק
  - quantity/unit/preparation חייבים להיות null

instructionGroups:
- אל תשאיר name=null. אם אין כותרת, השתמש בשם "הוראות".
- שמור על טקסט ההוראות כפי שמופיע, בלי להוסיף.

nutrition:
- אם אין ערכים תזונתיים בתמונה → החזר nutrition: null (אל תנחש).

תבנית דוגמה (להעתקה של שדות/מבנה בלבד):
{
  "title": null,
  "language": "he",
  "servings": null,
  "prepTimeMinutes": null,
  "cookTimeMinutes": null,
  "totalTimeMinutes": null,
  "ingredientGroups": [
    {
      "name": null,
      "ingredients": [
        {
          "quantity": null,
          "name": "",
          "unit": null,
          "preparation": null,
          "raw": ""
        }
      ]
    }
  ],
  "instructionGroups": [
    {
      "name": "הוראות",
      "instructions": [""]
    }
  ],
  "notes": [],
  "images": [],
  "nutrition": null
}
""".strip()

    def _build_generation_prompt(self, ingredients: List[str]) -> str:
        ingredients_text = "\n".join(f"- {ing}" for ing in ingredients)
        return f"""
צור מתכון מקורי ויצירתי עם המרכיבים הבאים:
{ingredients_text}

החזר אובייקט JSON תקין בלבד בתבנית Recipe.
ללא Markdown, ללא ``` , ללא טקסט לפני/אחרי ה-JSON.

כללים:
- אפשר להוסיף תבלינים בסיסיים (מלח/פלפל/שמן/תבלינים נפוצים) לפי הצורך.
- instructionGroups: לעולם אל תשאיר name=null.
- nutrition: הערך יכול להיות הערכה סבירה.

תבנית:
{{
  "title": null,
  "language": "he",
  "servings": null,
  "prepTimeMinutes": null,
  "cookTimeMinutes": null,
  "totalTimeMinutes": null,
  "ingredientGroups": [
    {{
      "name": null,
      "ingredients": [
        {{"quantity": null, "name": "", "unit": null, "preparation": null, "raw": null}}
      ]
    }}
  ],
  "instructionGroups": [
    {{"name": "הכנה", "instructions": [""]}}
  ],
  "notes": [],
  "images": [],
  "nutrition": {{
    "calories": 0,
    "protein_g": 0,
    "fat_g": 0,
    "carbs_g": 0,
    "per": "מנה"
  }}
}}
""".strip()

    def _build_text_generation_prompt(self, user_prompt: str) -> str:
        return f"""
המשתמש ביקש:
{user_prompt}

צור מתכון מתאים לבקשה.
החזר אובייקט JSON תקין בלבד בתבנית Recipe.
ללא Markdown, ללא ``` , ללא טקסט לפני/אחרי ה-JSON.

כללים:
- instructionGroups: לעולם אל תשאיר name=null.
- nutrition: הערך יכול להיות הערכה סבירה.

תבנית:
{{
  "title": null,
  "language": "he",
  "servings": null,
  "prepTimeMinutes": null,
  "cookTimeMinutes": null,
  "totalTimeMinutes": null,
  "ingredientGroups": [
    {{
      "name": null,
      "ingredients": [
        {{"quantity": null, "name": "", "unit": null, "preparation": null, "raw": null}}
      ]
    }}
  ],
  "instructionGroups": [
    {{"name": "הכנה", "instructions": [""]}}
  ],
  "notes": [],
  "images": [],
  "nutrition": {{
    "calories": 0,
    "protein_g": 0,
    "fat_g": 0,
    "carbs_g": 0,
    "per": "מנה"
  }}
}}
""".strip()

    def _build_nutrition_enrichment_prompt(self, recipe: Recipe) -> str:
        # Keep it simple and deterministic: “fill nutrition only”, don’t rewrite everything unless needed.
        recipe_dict = recipe.model_dump()
        # Ensure JSON serializable
        recipe_json = json.dumps(recipe_dict, ensure_ascii=False)

        return f"""
יש לך מתכון בפורמט JSON (Recipe). מלא/עדכן רק את השדה nutrition (הערכה סבירה),
מבלי לשנות את המרכיבים/הוראות/כותרות/קבוצות, אלא אם חייבים כדי לחשב.

החזר JSON תקין בלבד של כל האובייקט Recipe.
ללא Markdown, ללא ``` , ללא טקסט לפני/אחרי ה-JSON.

המתכון:
{recipe_json}
""".strip()

    # ---------------------------------------------------------------------
    # Core Gemini call + JSON guard + repair retries
    # ---------------------------------------------------------------------

    async def _generate_json_with_retries(
        self,
        *,
        model: str,
        contents: Any,
        schema: Dict[str, Any],
        temperature: float,
        max_retries: int = 2,
    ) -> Dict[str, Any]:
        """
        Calls Gemini and enforces:
        - Return must contain a valid JSON object
        - JSON must validate (at least parse) and be compatible with our normalization
        - If it fails, we ask Gemini to repair and retry.
        """
        last_text: Optional[str] = None
        last_err: Optional[str] = None

        for attempt in range(max_retries + 1):
            try:
                response_text = await self._call_gemini(
                    model=model,
                    contents=contents,
                    schema=schema,
                    temperature=temperature,
                )
                last_text = response_text

                json_text = self._extract_json_from_text(response_text)
                data = json.loads(json_text)

                # Basic sanity: must be dict
                if not isinstance(data, dict):
                    raise GeminiError("Gemini returned JSON that is not an object")

                # Try a lightweight validation by normalizing + constructing Recipe (strict guard)
                # NOTE: OCR-mode normalization is applied in the caller; here we just ensure it's close enough.
                normalized = self._normalize_recipe_json(data, ocr_mode=False)
                Recipe(**normalized)  # will raise ValidationError if schema is off

                return data

            except Exception as e:
                last_err = str(e)
                logger.warning(
                    "Gemini JSON attempt %d/%d failed: %s",
                    attempt + 1,
                    max_retries + 1,
                    last_err,
                )

                if attempt >= max_retries:
                    break

                # Build repair prompt: provide errors + previous output; force "JSON only".
                repair_prompt = self._build_repair_prompt(
                    error_message=last_err,
                    bad_output=last_text or "",
                    schema=schema,
                )

                # If original contents were a list (image+prompt), keep the image part and replace the prompt
                if isinstance(contents, list) and contents:
                    # assume first item is prompt, second is inline_data
                    fixed_contents = [repair_prompt] + contents[1:]
                    contents = fixed_contents
                else:
                    contents = repair_prompt

        raise GeminiError(f"Gemini could not produce valid JSON after retries. Last error: {last_err}")

    async def _call_gemini(
        self,
        *,
        model: str,
        contents: Any,
        schema: Dict[str, Any],
        temperature: float,
    ) -> str:
        """
        Single Gemini call. We *request* JSON via response_schema + application/json,
        but still handle messy returns using _extract_json_from_text.
        """
        def _sync_call() -> Any:
            return self.client.models.generate_content(
                model=model,
                contents=contents,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=schema,
                    temperature=temperature,
                ),
            )

        resp = await asyncio.to_thread(_sync_call)

        # Depending on SDK version, resp.text is usually present.
        text = getattr(resp, "text", None)
        if not text:
            raise GeminiError("Gemini returned empty response")
        logger.debug("Gemini raw response:\n%s", text)
        return text.strip()

    def _build_repair_prompt(self, *, error_message: str, bad_output: str, schema: Dict[str, Any]) -> str:
        schema_str = json.dumps(schema, ensure_ascii=False)
        return f"""
הפלט הקודם אינו JSON תקין / אינו תואם סכמת Recipe.

שגיאה:
{error_message}

הפלט הקודם (לתיקון):
{bad_output}

דרישות:
- החזר אובייקט JSON תקין בלבד (מתחיל ב-{{ ומסתיים ב-}}).
- ללא Markdown, ללא ``` , ללא טקסט לפני/אחרי.
- אל תשנה את המשמעות של הנתונים, רק תקן מבנה/שדות/טיפוסים כדי להתאים לסכמה.

סכמת JSON (לייחוס בלבד):
{schema_str}
""".strip()

    # ---------------------------------------------------------------------
    # Parsing / normalization
    # ---------------------------------------------------------------------

    def _extract_json_from_text(self, text: str) -> str:
        """Extract JSON object from text (handles accidental wrappers)."""
        t = text.strip()

        # Remove markdown code fences if they appear
        t = re.sub(r"^```json\s*", "", t, flags=re.IGNORECASE | re.MULTILINE)
        t = re.sub(r"^```\s*", "", t, flags=re.MULTILINE)
        t = re.sub(r"\s*```$", "", t, flags=re.MULTILINE).strip()

        # If already pure JSON
        if t.startswith("{") and t.endswith("}"):
            return t

        # Find first/last braces
        first = t.find("{")
        last = t.rfind("}")
        if first != -1 and last != -1 and last > first:
            return t[first:last + 1]

        return t

    def _normalize_recipe_json(self, recipe_json: Dict[str, Any], *, ocr_mode: bool) -> Dict[str, Any]:
        """
        Normalize recipe JSON to satisfy Pydantic model types.
        If ocr_mode=True:
          - Force ingredients to be raw-faithful (name=raw, quantity/unit/preparation=None).
          - Force nutrition to None if missing / invalid.
        """
        normalized: Dict[str, Any] = dict(recipe_json or {})

        # Ensure list fields exist
        for k in ("ingredientGroups", "instructionGroups", "notes", "images"):
            if normalized.get(k) is None:
                normalized[k] = []

        # Backward compatibility (if model expects it)
        normalized.setdefault("ingredients", [])

        # servings -> str
        if "servings" in normalized and normalized["servings"] is not None and not isinstance(normalized["servings"], str):
            normalized["servings"] = str(normalized["servings"])

        # images: remove empties
        imgs = normalized.get("images")
        if isinstance(imgs, list):
            normalized["images"] = [x for x in imgs if isinstance(x, str) and x.strip()]

        # instructionGroups: ensure name is not null
        igroups = normalized.get("instructionGroups")
        if isinstance(igroups, list):
            fixed = []
            for g in igroups:
                if not isinstance(g, dict):
                    continue
                g2 = dict(g)
                if not g2.get("name"):
                    g2["name"] = "הוראות"
                instr = g2.get("instructions")
                if instr is None:
                    g2["instructions"] = []
                elif isinstance(instr, list):
                    g2["instructions"] = [str(x).strip() for x in instr if str(x).strip()]
                else:
                    g2["instructions"] = [str(instr).strip()] if str(instr).strip() else []
                fixed.append(g2)
            normalized["instructionGroups"] = fixed

        # notes: ensure strings
        notes = normalized.get("notes")
        if isinstance(notes, list):
            normalized["notes"] = [str(x).strip() for x in notes if str(x).strip()]

        # ingredientGroups normalization
        groups = normalized.get("ingredientGroups")
        if isinstance(groups, list):
            fixed_groups = []
            for g in groups:
                if not isinstance(g, dict):
                    continue
                g2 = dict(g)
                ingr = g2.get("ingredients")

                normalized_ingredients: List[Dict[str, Any]] = []

                if isinstance(ingr, list):
                    for ing in ingr:
                        # Allow strings -> convert
                        if isinstance(ing, str):
                            raw = ing.strip()
                            obj = {
                                "name": raw,
                                "raw": raw,
                                "quantity": None,
                                "unit": None,
                                "preparation": None,
                            }
                            normalized_ingredients.append(obj)
                            continue

                        if isinstance(ing, dict):
                            raw_val = ing.get("raw")
                            name_val = ing.get("name")

                            # If OCR mode: enforce raw-faithful representation
                            if ocr_mode:
                                raw = (raw_val or name_val or "").strip()
                                if not raw:
                                    # skip empty
                                    continue
                                obj = {
                                    "name": raw,            # keep full line
                                    "raw": raw,
                                    "quantity": None,
                                    "unit": None,
                                    "preparation": None,
                                }
                                normalized_ingredients.append(obj)
                                continue

                            # Non-OCR mode: keep structured data if present, but fix obvious type issues
                            quantity = ing.get("quantity")
                            if quantity is not None and not isinstance(quantity, str):
                                quantity = str(quantity)

                            obj = {
                                "name": str(name_val or raw_val or "").strip(),
                                "raw": (str(raw_val).strip() if raw_val is not None else None),
                                "quantity": quantity,
                                "unit": ing.get("unit"),
                                "preparation": ing.get("preparation"),
                            }

                            # If name missing but raw exists, set name=raw
                            if not obj["name"] and obj["raw"]:
                                obj["name"] = obj["raw"]

                            # If still empty, skip
                            if not obj["name"] and not obj["raw"]:
                                continue

                            normalized_ingredients.append(obj)
                            continue

                        # Unknown type
                        raw = str(ing).strip()
                        if raw:
                            normalized_ingredients.append(
                                {"name": raw, "raw": raw, "quantity": None, "unit": None, "preparation": None}
                            )

                else:
                    # ingredients field missing or wrong type
                    normalized_ingredients = []

                g2["ingredients"] = normalized_ingredients
                fixed_groups.append(g2)

            normalized["ingredientGroups"] = fixed_groups

        # nutrition handling
        if ocr_mode:
            # do not guess nutrition in OCR mode
            normalized["nutrition"] = None
        else:
            # if nutrition is present but malformed, keep it as-is; Recipe validation will enforce correctness
            pass

        return normalized
