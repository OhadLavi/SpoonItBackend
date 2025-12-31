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
        Extract recipe from image using a 2-pass approach:
        (1) strict transcription (no guessing; ??? for unreadable)
        (2) structuring only from that transcription (prevents hallucinations)
        """
        try:
            logger.info(f"Extracting recipe from image (mime_type: {mime_type})")

            processed_bytes, processed_mime = self._preprocess_image_for_handwriting(image_data, mime_type)
            image_b64 = base64.b64encode(processed_bytes).decode("utf-8")

            transcript = await self._transcribe_recipe_text_from_image(
                image_base64=image_b64,
                mime_type=processed_mime,
            )

            recipe_json = await self._structure_recipe_from_transcript(transcript)

            normalized = self._normalize_recipe_json(recipe_json)
            return Recipe(**normalized)

        except Exception as e:
            logger.error(f"Image extraction failed: {str(e)}", exc_info=True)
            raise GeminiError(f"Failed to extract recipe from image: {str(e)}") from e

    async def generate_recipe_from_ingredients(self, ingredients: List[str]) -> Recipe:
        prompt = self._build_generation_prompt(ingredients)
        try:
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                None,
                lambda: self.client.models.generate_content(
                    model=settings.gemini_model,
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        temperature=settings.gemini_temperature,
                        response_mime_type="application/json",
                        response_schema=self._clean_schema_for_gemini(Recipe.model_json_schema()),
                    ),
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
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                None,
                lambda: self.client.models.generate_content(
                    model=settings.gemini_model,
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        temperature=settings.gemini_temperature,
                        response_mime_type="application/json",
                        response_schema=self._clean_schema_for_gemini(Recipe.model_json_schema()),
                    ),
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
    # Pass A: strict transcription
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

        response = await loop.run_in_executor(
            None,
            lambda: self.client.models.generate_content(
                model=model_for_ocr,
                contents=[
                    prompt,
                    {"inline_data": {"mime_type": mime_type, "data": image_base64}},
                ],
                config=types.GenerateContentConfig(
                    temperature=0.0,
                    response_mime_type="application/json",
                    response_schema=transcript_schema,
                ),
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

        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None,
            lambda: self.client.models.generate_content(
                model=settings.gemini_model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=0.0,
                    response_mime_type="application/json",
                    response_schema=self._clean_schema_for_gemini(Recipe.model_json_schema()),
                ),
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

        # Map alternate top-level keys if they appear
        if "prepTime" in normalized and "prepTimeMinutes" not in normalized:
            normalized["prepTimeMinutes"] = normalized.pop("prepTime") or None
        if "cookTime" in normalized and "cookTimeMinutes" not in normalized:
            normalized["cookTimeMinutes"] = normalized.pop("cookTime") or None
        if "totalTime" in normalized and "totalTimeMinutes" not in normalized:
            normalized["totalTimeMinutes"] = normalized.pop("totalTime") or None

        # Ensure list fields exist and have correct types
        normalized["images"] = self._ensure_string_list(normalized.get("images"))
        normalized["notes"] = self._ensure_string_list(normalized.get("notes"))  # <-- fixes your Pydantic error
        normalized.setdefault("ingredientGroups", [])
        normalized.setdefault("instructionGroups", [])
        normalized.setdefault("ingredients", [])  # backward compat in your model

        # servings -> str or None
        if "servings" in normalized and normalized["servings"] is not None and not isinstance(normalized["servings"], str):
            normalized["servings"] = str(normalized["servings"])

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

        # Compute total time if missing and parts exist
        if normalized.get("totalTimeMinutes") is None:
            pt = normalized.get("prepTimeMinutes") or 0
            ct = normalized.get("cookTimeMinutes") or 0
            if isinstance(pt, (int, float)) and isinstance(ct, (int, float)) and (pt or ct):
                normalized["totalTimeMinutes"] = int(pt + ct)

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
                                "quantity": None,
                                "unit": None,
                                "preparation": None,
                                "raw": ing,
                            }
                        )
                        continue

                    if not isinstance(ing, dict):
                        normalized_ingredients.append({"name": str(ing), "quantity": None, "unit": None, "preparation": None, "raw": str(ing)})
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

                    qty = ing.get("quantity")
                    if qty is not None and not isinstance(qty, str):
                        qty = str(qty)

                    unit = ing.get("unit")
                    if unit == "":
                        unit = None
                    if unit is not None and not isinstance(unit, str):
                        unit = str(unit)

                    # ingredient notes -> preparation (best fit in your schema)
                    prep = ing.get("preparation")
                    if prep is None:
                        prep = ing.get("notes")
                    if prep is not None and not isinstance(prep, str):
                        prep = str(prep)

                    normalized_ingredients.append(
                        {
                            "name": ing_name or "",
                            "quantity": qty,
                            "unit": unit,
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

    def _ensure_nutrition_object(self, nutrition: Any) -> Dict[str, Any]:
        """
        Normalize nutrition to your schema:
          calories, protein_g, fat_g, carbs_g, per
        Accepts variants like protein/carbohydrates/fat.
        """
        def _f(x: Any) -> float:
            try:
                return float(x)
            except Exception:
                return 0.0

        if not isinstance(nutrition, dict):
            return {"calories": 0, "protein_g": 0, "fat_g": 0, "carbs_g": 0, "per": "מנה"}

        calories = nutrition.get("calories", 0)

        # variants
        protein = nutrition.get("protein_g", nutrition.get("protein", 0))
        fat = nutrition.get("fat_g", nutrition.get("fat", 0))
        carbs = nutrition.get("carbs_g", nutrition.get("carbohydrates", nutrition.get("carbs", 0)))

        per = nutrition.get("per") or "מנה"

        return {
            "calories": _f(calories),
            "protein_g": _f(protein),
            "fat_g": _f(fat),
            "carbs_g": _f(carbs),
            "per": per,
        }

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
