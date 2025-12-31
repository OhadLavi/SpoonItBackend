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

            # Pass A: Transcribe
            transcript = await self._transcribe_recipe_text_from_image(
                image_base64=image_b64,
                mime_type=processed_mime,
            )

            # Pass B: Structure strictly from transcript text (no extra info)
            recipe_json = await self._structure_recipe_from_transcript(transcript)

            normalized = self._normalize_recipe_json(recipe_json)
            return Recipe(**normalized)

        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse JSON from image extraction: {str(e)}")
            raise GeminiError(f"Failed to parse recipe JSON from image: {str(e)}") from e
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
                        response_mime_type="text/plain",
                    ),
                ),
            )
            if response is None or response.text is None:
                raise GeminiError("Gemini returned empty response for recipe generation")

            json_text = self._extract_json_from_text(response.text)
            recipe_json = json.loads(json_text)
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
                        response_mime_type="text/plain",
                    ),
                ),
            )
            if response is None or response.text is None:
                raise GeminiError("Gemini returned empty response for text generation")

            json_text = self._extract_json_from_text(response.text)
            recipe_json = json.loads(json_text)
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
- שמור על סדר השורות כפי שמופיע.
- אל תוסיף שום מידע שלא קיים בתמונה.

החזר JSON בלבד (ללא markdown וללא הסברים) עם המפתחות הבאים בלבד:
- title: string או null
- ingredients_lines: רשימת שורות של מרכיבים (strings)
- instructions_lines: רשימת שורות של הוראות/טקסט הכנה (strings)
- other_lines: כל שורה אחרת שלא בטוח לאיזה חלק שייכת (strings)
""".strip()

        loop = asyncio.get_event_loop()
        # Use a stronger model for handwriting OCR if you have one (pro often better)
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
                    response_mime_type="text/plain",
                ),
            ),
        )

        if response is None or response.text is None or not response.text.strip():
            raise GeminiError("Gemini returned empty response for transcription")

        raw = response.text.strip()
        logger.info(f"Gemini transcription raw:\n{raw}")

        json_text = self._extract_json_from_text(raw)
        data = json.loads(json_text)

        # Minimal sanity normalization
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
אתה חייב לבנות אובייקט Recipe JSON רק מתוך התמלול הזה.
אסור להוסיף שום מרכיב/שלב שלא קיים בתמלול.

תמלול:
- title: {title}
- ingredients_lines:
{json.dumps(ingredients_lines, ensure_ascii=False)}
- instructions_lines:
{json.dumps(instructions_lines, ensure_ascii=False)}
- other_lines:
{json.dumps(other_lines, ensure_ascii=False)}

כללים נוקשים:
- ingredientGroups: צור קבוצה אחת לפחות, וכל מרכיב חייב להופיע ב-raw בדיוק כמו בשורה בתמלול.
- instructionGroups: צור קבוצה אחת לפחות, ו-instructions חייב להיות רשימת צעדים (List[str]).
  אם ההוראות בפסקה אחת/שורה אחת: חלק לצעדים קצרים בלי להמציא (רק פיצול).
- nutrition: אם אי אפשר לחשב בוודאות על סמך התמלול, החזר ערכים מספריים 0 ו-per="מנה" (לא null).
- החזר JSON בלבד. ללא markdown. ללא הסברים. ללא טקסט נוסף.
""".strip()

        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None,
            lambda: self.client.models.generate_content(
                model=settings.gemini_model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=0.0,
                    response_mime_type="text/plain",
                ),
            ),
        )

        if response is None or response.text is None or not response.text.strip():
            raise GeminiError("Gemini returned empty response for structuring from transcript")

        raw = response.text.strip()
        logger.info(f"Gemini structured-from-transcript raw:\n{raw}")

        json_text = self._extract_json_from_text(raw)
        return json.loads(json_text)

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
ללא markdown. ללא הסברים.
""".strip()

    def _build_text_generation_prompt(self, user_prompt: str) -> str:
        return f"""
המשתמש ביקש:
{user_prompt}

צור מתכון מתאים לבקשה והחזר JSON תקין בלבד לפי מודל Recipe.
- instructionGroups.instructions חייב להיות רשימת צעדים (לא פסקה אחת).
- nutrition חייב להיות אובייקט מלא עם מספרים (אם לא בטוח -> 0).
ללא markdown. ללא הסברים.
""".strip()

    # --------------------------
    # Parsing helpers
    # --------------------------

    def _extract_json_from_text(self, text: str) -> str:
        text = (text or "").strip()
        text = re.sub(r"^```json\s*", "", text, flags=re.MULTILINE)
        text = re.sub(r"^```\s*", "", text, flags=re.MULTILINE)
        text = text.strip()

        if text.startswith("{") and text.endswith("}"):
            return text

        first = text.find("{")
        last = text.rfind("}")
        if first != -1 and last != -1 and last > first:
            return text[first : last + 1]
        return text

    # --------------------------
    # Normalization
    # --------------------------

    def _normalize_recipe_json(self, recipe_json: Dict[str, Any]) -> Dict[str, Any]:
        normalized: Dict[str, Any] = dict(recipe_json or {})

        for k in ("ingredientGroups", "instructionGroups", "notes", "images"):
            if normalized.get(k) is None:
                normalized[k] = []

        normalized.setdefault("ingredients", [])

        if "servings" in normalized and normalized["servings"] is not None and not isinstance(normalized["servings"], str):
            normalized["servings"] = str(normalized["servings"])

        imgs = normalized.get("images")
        if isinstance(imgs, list):
            normalized["images"] = [x for x in imgs if isinstance(x, str) and x.strip()]

        # Normalize ingredientGroups
        ig = normalized.get("ingredientGroups")
        if isinstance(ig, list):
            fixed_groups = []
            for g in ig:
                if not isinstance(g, dict):
                    continue
                ingr = g.get("ingredients")
                if isinstance(ingr, list):
                    out_ing = []
                    for ing in ingr:
                        if isinstance(ing, str):
                            out_ing.append({"name": ing, "raw": ing})
                        elif isinstance(ing, dict):
                            # keep raw exact if exists
                            raw = ing.get("raw")
                            name = ing.get("name") or (raw or "")
                            quantity = ing.get("quantity")
                            if quantity is not None and not isinstance(quantity, str):
                                quantity = str(quantity)
                            out_ing.append(
                                {
                                    "name": name,
                                    "quantity": quantity,
                                    "unit": ing.get("unit"),
                                    "preparation": ing.get("preparation"),
                                    "raw": raw or name,
                                }
                            )
                        else:
                            out_ing.append({"raw": str(ing)})
                    g = dict(g)
                    g["ingredients"] = out_ing
                fixed_groups.append(g)
            normalized["ingredientGroups"] = fixed_groups

        # Normalize instructionGroups + ensure multi-step
        normalized["instructionGroups"] = self._normalize_instruction_groups(normalized.get("instructionGroups"))

        # Ensure nutrition is never null
        normalized["nutrition"] = self._ensure_nutrition_object(normalized.get("nutrition"))

        return normalized

    def _ensure_nutrition_object(self, nutrition: Any) -> Dict[str, Any]:
        if isinstance(nutrition, dict):
            def _f(x: Any) -> float:
                try:
                    return float(x)
                except Exception:
                    return 0.0

            return {
                "calories": _f(nutrition.get("calories", 0)),
                "protein_g": _f(nutrition.get("protein_g", 0)),
                "fat_g": _f(nutrition.get("fat_g", 0)),
                "carbs_g": _f(nutrition.get("carbs_g", 0)),
                "per": nutrition.get("per") or "מנה",
            }
        return {"calories": 0, "protein_g": 0, "fat_g": 0, "carbs_g": 0, "per": "מנה"}

    def _normalize_instruction_groups(self, groups: Any) -> List[Dict[str, Any]]:
        if not isinstance(groups, list):
            return [{"name": "הוראות", "instructions": []}]

        out: List[Dict[str, Any]] = []
        for g in groups:
            if not isinstance(g, dict):
                continue

            name = g.get("name") or "הוראות"
            instr = g.get("instructions")

            steps: List[str] = []
            if isinstance(instr, str):
                steps = self._split_to_steps(instr)
            elif isinstance(instr, list):
                for item in instr:
                    if isinstance(item, str):
                        steps.extend(self._split_to_steps(item))

            steps = [s.strip() for s in steps if isinstance(s, str) and s.strip()]

            # If still one big paragraph -> force a slightly more aggressive split
            if len(steps) == 1:
                forced = self._split_to_steps(steps[0], aggressive=True)
                forced = [s.strip() for s in forced if s.strip()]
                if len(forced) > 1:
                    steps = forced

            if steps:
                out.append({"name": name, "instructions": steps})

        if not out:
            out = [{"name": "הוראות", "instructions": []}]
        return out

    def _split_to_steps(self, text: str, aggressive: bool = False) -> List[str]:
        """
        Step splitting WITHOUT verb lists.
        Uses:
          - punctuation (.!?)
          - explicit separators (newline, ';', ' - ')
          - sequencing words (ואז / אחר כך / לאחר מכן)
          - optional comma splitting only when it likely contains multiple actions
        """
        t = (text or "").strip()
        if not t:
            return []

        # Normalize whitespace
        t = re.sub(r"\s+", " ", t)

        # Insert split markers for sequencing words
        if aggressive:
            t = re.sub(r"\s+(ואז|אחר כך|לאחר מכן)\s+", r" | \1 ", t)

        # Split by sentence punctuation
        parts = re.split(r"(?<=[\.\!\?])\s+", t)

        # Expand by common separators
        expanded: List[str] = []
        for p in parts:
            p = p.strip()
            if not p:
                continue
            for sep in ["\n", ";", " - ", " – ", " — "]:
                if sep in p:
                    tmp = []
                    for chunk in p.split(sep):
                        c = chunk.strip()
                        if c:
                            tmp.append(c)
                    p = " | ".join(tmp)
            expanded.extend([x.strip() for x in p.split("|") if x.strip()])

        final_steps: List[str] = []
        for p in expanded:
            p = p.strip()
            if not p:
                continue

            # Comma splitting only if it likely contains multiple actions/time segments
            if "," in p and (aggressive or self._likely_multi_step_clause(p)):
                chunks = [c.strip() for c in p.split(",") if c.strip()]
                # Merge tiny fragments to avoid garbage steps
                merged: List[str] = []
                for c in chunks:
                    if merged and len(c) < 6:
                        merged[-1] = f"{merged[-1]}, {c}"
                    else:
                        merged.append(c)
                final_steps.extend(merged)
            else:
                final_steps.append(p)

        # Clean duplicates / empties
        cleaned: List[str] = []
        for s in final_steps:
            s = re.sub(r"\s+", " ", s).strip()
            if s:
                cleaned.append(s)

        return cleaned

    def _likely_multi_step_clause(self, s: str) -> bool:
        """
        No verbs list. Use generic signals:
          - multiple time tokens
          - multiple commas
          - contains 'ול' + time/temperature patterns
        """
        if s.count(",") >= 2:
            return True

        # time/temperature signals
        time_hits = len(re.findall(r"\b\d+\s*(דק|דק'|דקות|שעה|שעות)\b", s))
        temp_hits = len(re.findall(r"\b\d+\s*(מעלות|°)\b", s))

        if time_hits + temp_hits >= 2:
            return True

        if " ול" in s and (time_hits + temp_hits >= 1):
            return True

        if " ואז " in s or " אחר כך " in s or " לאחר מכן " in s:
            return True

        return False

    # --------------------------
    # Image preprocessing (handwriting)
    # --------------------------

    def _preprocess_image_for_handwriting(self, image_bytes: bytes, mime_type: str) -> Tuple[bytes, str]:
        """
        Lightweight preprocessing that often improves handwritten OCR:
          - exif transpose
          - grayscale
          - autocontrast
          - mild sharpen/contrast
          - resize to a sane max dimension
        If Pillow not available -> return original.
        """
        if not _PIL_AVAILABLE:
            return image_bytes, mime_type

        try:
            img = Image.open(BytesIO(image_bytes))
            img = ImageOps.exif_transpose(img)

            # Convert to grayscale to focus ink
            img = img.convert("L")

            # Autocontrast helps pen on paper
            img = ImageOps.autocontrast(img, cutoff=2)

            # Slight contrast boost
            img = ImageEnhance.Contrast(img).enhance(1.35)

            # Slight sharpness
            img = ImageEnhance.Sharpness(img).enhance(1.25)

            # Resize (too large wastes tokens/time; too small loses strokes)
            max_dim = 1800
            w, h = img.size
            scale = min(1.0, max_dim / max(w, h))
            if scale < 1.0:
                img = img.resize((int(w * scale), int(h * scale)))

            out = BytesIO()
            # PNG tends to preserve handwriting better than JPEG artifacts
            img.save(out, format="PNG", optimize=True)
            return out.getvalue(), "image/png"

        except Exception as e:
            logger.warning(f"Image preprocess failed, using original: {e}")
            return image_bytes, mime_type
