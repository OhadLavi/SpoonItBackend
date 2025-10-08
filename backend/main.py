# main.py
from __future__ import annotations

import asyncio
import base64
import io
import json
import logging
import re
from typing import Optional, Dict, Any, List, Iterable, Tuple

import httpx
import uvicorn
from bs4 import BeautifulSoup, NavigableString, Tag
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from PIL import Image, ImageOps, ImageFilter
from pydantic import BaseModel, Field
from playwright.async_api import async_playwright
import pytesseract

# =============================================================================
# Logging
# =============================================================================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
    handlers=[logging.FileHandler("recipe_keeper.log", encoding="utf-8"), logging.StreamHandler()],
)
logger = logging.getLogger("recipe-keeper")

# =============================================================================
# Config
# =============================================================================
OLLAMA_API_URL = "http://127.0.0.1:11434/api/generate"
MODEL_NAME = "gemma3:4b"
HTTP_TIMEOUT = 30.0
PLAYWRIGHT_TIMEOUT_MS = 35000
FETCH_MAX_BYTES = 2_500_000  # ~2.5MB safety cap

# =============================================================================
# Errors
# =============================================================================
class APIError(Exception):
    def __init__(self, message: str, status_code: int = 500, details: Optional[Dict[str, Any]] = None):
        super().__init__(message)
        self.message = message
        self.status_code = status_code
        self.details = details or {}

# =============================================================================
# Schemas
# =============================================================================
class ChatRequest(BaseModel):
    message: str
    language: str = "en"

class RecipeExtractionRequest(BaseModel):
    url: str

class ImageExtractionRequest(BaseModel):
    image_data: str  # base64 (with or without data URI prefix)

class CustomRecipeRequest(BaseModel):
    groceries: str
    description: str

class RecipeModel(BaseModel):
    title: str = ""
    description: str = ""
    ingredients: List[str] = Field(default_factory=list, min_length=0)
    instructions: List[str] = Field(default_factory=list, min_length=0)
    prepTime: int = 0
    cookTime: int = 0
    servings: int = 1
    tags: List[str] = Field(default_factory=list, min_length=0)
    notes: str = ""
    source: str = ""
    imageUrl: str = ""

# =============================================================================
# Utils & Normalization
# =============================================================================
HEBREW_NUMBERS = {
    "אחד": 1, "אחת": 1, "שתיים": 2, "שניים": 2, "שתים": 2, "שלוש": 3, "שלושה": 3,
    "ארבע": 4, "ארבעה": 4, "חמש": 5, "חמישה": 5, "שש": 6, "שישה": 6, "שבע": 7, "שבעה": 7,
    "שמונה": 8, "תשע": 9, "עשר": 10,
}

FRACTIONS_CHARS = "¼½¾⅓⅔⅛⅜⅝⅞"
MEASURE_RE = re.compile(
    rf"""(?x)
    (?:\d+\s*(?:/\s*\d+)?|[{FRACTIONS_CHARS}])\s*
    (?:גרם|ג['׳]?|מ\"?ל|ml|כפ(?:ית|יות|ה|ות)|כוס(?:ות)?|טיפ(?:ה|ות)|
       שק(?:ית|יות)|חביל(?:ה|ות)|אריז(?:ה|ות)?|קוב(?:יה|יות)|יחיד(?:ה|ות)|
       פרוס(?:ה|ות)|ביצ(?:ה|ים)?|קורט)
    """,
    re.IGNORECASE,
)
NUMBERY_RE = re.compile(r"\d")

ING_HEADERS = [
    "רכיבים", "מצרכים", "מרכיבים", "מצרכים למתכון",
    "ingredients", "ingredient", "what you need",
]
STEP_HEADERS = [
    "אופן ההכנה", "אופן הכנה", "הוראות הכנה", "הוראות", "הכנה",
    "כיצד מכינים", "שיטה", "הכנות", "Preparation", "Directions", "Instructions", "Method",
]
STOP_LABELS = STEP_HEADERS + [
    "טיפים", "טיפים והערות", "הערות", "שיתוף", "עוד מתכונים",
    "ערכים תזונתיים", "הערך התזונתי", "קלוריות", "ציוד נדרש", "ציוד",
    "תגובות", "סרטון", "סרטונים", "שלח לחבר", "הדפסה", "AI המלצות", "חדש",
]

def safe_strip(v: Any) -> str:
    return "" if v is None else str(v).strip()

def clean_html(text: Any) -> str:
    s = safe_strip(text)
    if not s:
        return ""
    return BeautifulSoup(s, "html.parser").get_text(separator=" ", strip=True)

def _limit_size(s: str, max_bytes: int = FETCH_MAX_BYTES) -> str:
    b = s.encode("utf-8", errors="ignore")
    if len(b) <= max_bytes:
        return s
    logger.info("[FETCH] truncated HTML from %d KB to %d KB", len(b)//1024, max_bytes//1024)
    return b[:max_bytes].decode("utf-8", errors="ignore")

def ensure_list(value: Any) -> list:
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return list(value.values())
    return [value] if value else []

def extract_unique_lines(lines: Iterable[str]) -> List[str]:
    seen = set()
    out: List[str] = []
    for line in lines:
        line = clean_html(line)
        if not line:
            continue
        key = line.lower()
        if key not in seen:
            seen.add(key)
            out.append(line)
    return out

def remove_exact_duplicates(seq: List[str]) -> List[str]:
    seen = set()
    out: List[str] = []
    for item in seq:
        if item not in seen:
            seen.add(item)
            out.append(item)
    return out

def normalize_ingredient(item: Any) -> str:
    if item is None:
        return ""
    if isinstance(item, str):
        return clean_html(item)
    if isinstance(item, dict):
        name = clean_html(item.get("name") or item.get("item"))
        quantity = clean_html(item.get("quantity"))
        unit = clean_html(item.get("unit"))
        notes = clean_html(item.get("notes"))
        parts = [p for p in [name, quantity, unit] if p]
        if notes:
            parts.append(f"({notes})")
        return " ".join(parts).strip()
    return clean_html(item)

def convert_to_int(num_str: Any) -> int:
    s = safe_strip(num_str)
    if not s:
        return 0
    m = re.search(r"(\d+)\s*-\s*(\d+)", s)
    if m:
        return max(int(m.group(1)), int(m.group(2)))
    try:
        return int(s)
    except ValueError:
        for word, val in HEBREW_NUMBERS.items():
            if word in s:
                return val
    return 0

def parse_time_value(time_str: Any) -> int:
    """
    Returns minutes; handles:
      - "35-40 דקות"
      - "שעה ו-10 דקות", "1 שעה 20 דקות"
      - hr/hour/min variations + Hebrew
    """
    s = clean_html(time_str).lower()
    if not s:
        return 0

    m = re.search(r"(\d+)\s*-\s*(\d+)\s*(?:דק(?:ה|ות)?|min|minutes?)", s)
    if m:
        return max(int(m.group(1)), int(m.group(2)))

    mh = re.search(r"(\d+)\s*(?:שעה(?:ות)?|hr|hour|hours)", s)
    add_minutes = 0
    if mh:
        add_minutes += int(mh.group(1)) * 60
    elif "שעה" in s and not mh:
        add_minutes += 60

    mm = re.findall(r"(\d+)\s*(?:דק(?:ה|ות)?|min|minutes?)", s)
    if mm:
        add_minutes += int(mm[0])

    if add_minutes:
        return add_minutes

    m2 = re.search(r"(\d+)\s*(?:דק(?:ה|ות)?|min|minutes?)", s)
    if m2:
        return int(m2.group(1))

    m3 = re.search(r"(\d+)", s)
    if m3:
        return int(m3.group(1))
    return 0

def parse_servings(servings_str: Any) -> int:
    s = clean_html(servings_str).lower()
    if not s:
        return 1
    m = re.search(r"(\d+)", s)
    if m:
        return int(m.group(1))
    for word, val in HEBREW_NUMBERS.items():
        if word in s:
            return val
    return 1

# =============================================================================
# HTML helpers
# =============================================================================
def _find_first_matching_label(soup: BeautifulSoup, labels: List[str]) -> Optional[Tag]:
    for tag in soup.find_all(["h1", "h2", "h3", "h4", "strong", "p", "span", "div"]):
        txt = clean_html(tag.get_text())
        if any(lbl.lower() in txt.lower() for lbl in labels):
            return tag
    return None

def _text_lines_from_tag(tag: Tag) -> List[str]:
    lines: List[str] = []
    if tag.name in ("ul", "ol"):
        for li in tag.find_all("li"):
            t = clean_html(li.get_text())
            if t:
                lines.append(t)
        return lines

    # table → flatten rows
    if tag.name == "table":
        for tr in tag.find_all("tr"):
            cells = [clean_html(td.get_text()) for td in tr.find_all(["td", "th"])]
            row = " ".join([c for c in cells if c])
            if row:
                lines.append(row)
        return lines

    txt = tag.get_text(separator="\n", strip=True)
    for line in txt.split("\n"):
        line = clean_html(line)
        if line:
            lines.append(line)
    return lines

def _collect_after(start: Tag, stop_labels: List[str], max_nodes: int = 160) -> List[str]:
    """Collect texty blocks after a header until another header/stop label appears."""
    lines: List[str] = []
    nodes = 0
    for sib in start.next_siblings:
        if isinstance(sib, NavigableString):
            text = clean_html(str(sib))
            for ln in text.split("\n"):
                ln = clean_html(ln)
                if not ln:
                    continue
                if any(lbl.lower() in ln.lower() for lbl in stop_labels):
                    return lines
                lines.append(ln)
            continue

        if not isinstance(sib, Tag):
            continue

        nodes += 1
        if nodes > max_nodes:
            break

        text = clean_html(sib.get_text())
        if not text:
            continue

        # reached another header / stop area
        if any(lbl.lower() in text.lower() for lbl in stop_labels):
            break

        # prefer structured children first
        if sib.name in ("ul", "ol", "table"):
            lines.extend(_text_lines_from_tag(sib))
            continue

        # also gather within blocks
        for ln in _text_lines_from_tag(sib):
            if any(lbl.lower() in ln.lower() for lbl in stop_labels):
                return lines
            if ln in ("שיתוף", "הדפסה"):
                continue
            lines.append(ln)

    return lines

# =============================================================================
# Ingredient & Instruction normalization
# =============================================================================
def _has_measure(s: str) -> bool:
    s = clean_html(s)
    if not s:
        return False
    return bool(MEASURE_RE.search(s)) or "קורט" in s

def _stitch_broken_ingredient_lines(lines: List[str]) -> List[str]:
    """Join lines where the amount/notes were pushed to the next line."""
    out: List[str] = []
    for ln in lines:
        ln = clean_html(ln)
        if not ln:
            continue
        if out and not _has_measure(out[-1]) and (_has_measure(ln) or ln.startswith("(") or ln.startswith("או ")):
            out[-1] = (out[-1] + " " + ln).strip()
        elif out and not _has_measure(out[-1]) and re.match(r"^\d", ln):
            out[-1] = (out[-1] + " " + ln).strip()
        else:
            out.append(ln)
    return out

def _filter_to_measured_ingredients(lines: List[str]) -> List[str]:
    """Drop 'brand suggestions' and keep true ingredients with amounts."""
    stitched = _stitch_broken_ingredient_lines(lines)
    measured = [x for x in stitched if _has_measure(x) or NUMBERY_RE.search(x)]
    # If we were too strict and ended up with too little, relax slightly but still avoid obvious brand lists
    if len(measured) < 2:
        measured = [x for x in stitched if _has_measure(x) or "לפי הטעם" in x or "קורט" in x]
    # Final dedupe/clean
    measured = [re.sub(r"\s{2,}", " ", x).strip("•-—· ").strip() for x in measured]
    return extract_unique_lines([x for x in measured if len(x) > 1])

def _normalize_instruction_lines(lines: List[str]) -> List[str]:
    """Turn <ol>/<ul> or '1 ...'/'2 ...' blocks into clean steps with wrapping support."""
    # prefer li-based segmentation first
    li_like: List[str] = []
    for raw in lines:
        # split numbered paragraphs into pseudo-li
        m = re.match(r"^\s*(\d+)[\.\)]?\s*(.*)$", clean_html(raw))
        if m:
            li_like.append(f"{m.group(1)}. {m.group(2).strip()}")
        else:
            li_like.append(clean_html(raw))

    # collapse to numbered steps
    steps: List[str] = []
    buf = ""
    last_num = None
    for ln in li_like:
        if not ln:
            continue
        m = re.match(r"^\s*(\d+)[\.\)]\s+(.*)$", ln)
        if m:
            # boundary
            if buf:
                steps.append(buf.strip())
                buf = ""
            last_num = int(m.group(1))
            buf = m.group(2).strip()
        else:
            # continuation line (avoid meta)
            if any(x in ln for x in ("סוג המנה", "דרגת קושי", "זמן הכנה", "כשרות")):
                continue
            if buf:
                sep = " " if not ln.startswith("(") else " "
                buf += sep + ln
            else:
                buf = ln
    if buf:
        steps.append(buf.strip())

    # If we didn't detect numbers, fallback to bulletish grouping by sentence-ish lines
    if not steps:
        for ln in lines:
            t = clean_html(ln)
            if len(t) > 2:
                steps.append(t)
    steps = [re.sub(r"\s{2,}", " ", s).strip("•-—· ").strip() for s in steps]
    return remove_exact_duplicates([s for s in steps if len(s) > 2])

# =============================================================================
# Schema.org fast path
# =============================================================================
def parse_schema_org_recipe(html: str) -> Optional[RecipeModel]:
    try:
        soup = BeautifulSoup(html, "html.parser")
        scripts = soup.find_all("script", type="application/ld+json")
        logger.info("[SCHEMA] found %d ld+json scripts", len(scripts))
        for sc in scripts:
            raw = sc.string or sc.get_text() or ""
            if not raw.strip():
                continue
            try:
                data = json.loads(raw)
            except Exception:
                continue
            candidates = data if isinstance(data, list) else [data]
            flat: List[dict] = []
            for obj in candidates:
                if isinstance(obj, dict) and "@graph" in obj:
                    flat.extend([x for x in obj.get("@graph", []) if isinstance(x, dict)])
                if isinstance(obj, dict):
                    flat.append(obj)
            for obj in flat:
                typ = obj.get("@type") or obj.get("type")
                is_recipe = False
                if isinstance(typ, list):
                    is_recipe = any(isinstance(t, str) and t.lower() == "recipe" for t in typ)
                elif isinstance(typ, str):
                    is_recipe = typ.lower() == "recipe"
                if not is_recipe:
                    continue

                title = clean_html(obj.get("name"))
                description = clean_html(obj.get("description"))

                image_url = ""
                img = obj.get("image")
                if isinstance(img, str):
                    image_url = img
                elif isinstance(img, list) and img and isinstance(img[0], str):
                    image_url = img[0]
                elif isinstance(img, dict):
                    image_url = clean_html(img.get("url"))

                ings = ensure_list(obj.get("recipeIngredient") or obj.get("ingredients"))
                ings = [normalize_ingredient(x) for x in ings if x]
                ings = extract_unique_lines(ings)

                instr: List[str] = []
                ri = obj.get("recipeInstructions")
                if isinstance(ri, list):
                    for step in ri:
                        if isinstance(step, dict):
                            txt = clean_html(step.get("text") or step.get("name"))
                        else:
                            txt = clean_html(step)
                        if txt:
                            instr.append(txt)
                elif isinstance(ri, str):
                    instr = [clean_html(x) for x in ri.split("\n") if clean_html(x)]
                instr = remove_exact_duplicates(instr)

                def _duration_to_min(v: str) -> int:
                    v = v or ""
                    m = re.search(r"PT(?:(\d+)H)?(?:(\d+)M)?", v, re.I)
                    if m:
                        return (int(m.group(1) or 0) * 60) + int(m.group(2) or 0)
                    return parse_time_value(v)

                prep = _duration_to_min(safe_strip(obj.get("prepTime")))
                cook = _duration_to_min(safe_strip(obj.get("cookTime")))
                servings = parse_servings(obj.get("recipeYield"))

                tags: List[str] = []
                kw = obj.get("keywords")
                if isinstance(kw, str):
                    tags = [clean_html(x) for x in kw.split(",") if clean_html(x)]
                elif isinstance(kw, list):
                    tags = [clean_html(x) for x in kw if clean_html(x)]

                model = RecipeModel(
                    title=title,
                    description=description,
                    ingredients=ings,
                    instructions=instr,
                    prepTime=prep,
                    cookTime=cook,
                    servings=servings,
                    tags=tags,
                    imageUrl=image_url,
                )
                logger.info("[SCHEMA] success | title='%s' ings=%d steps=%d", model.title or "", len(model.ingredients), len(model.instructions))
                return model
    except Exception as e:
        logger.debug("[SCHEMA] parse failed: %s", e, exc_info=True)
    logger.info("[SCHEMA] not found")
    return None

# =============================================================================
# Generic HTML extraction (lists + tables)
# =============================================================================
def _extract_ingredient_candidates(soup: BeautifulSoup) -> List[str]:
    lines: List[str] = []

    # 1) Prefer sections after recognized "ingredients" headers
    ing_header = _find_first_matching_label(soup, ING_HEADERS)
    if ing_header:
        lines.extend(_collect_after(ing_header, stop_labels=STOP_LABELS, max_nodes=220))

    # 2) Also scan nearby tables (site like Foodsdictionary keeps amounts in tables)
    # Choose tables with at least 2 rows that look measure-ish
    for tbl in soup.find_all("table"):
        rows = _text_lines_from_tag(tbl)
        score = sum(1 for r in rows if _has_measure(r) or NUMBERY_RE.search(r))
        if score >= 2:
            lines.extend(rows)

    # 3) Fallback: any UL/OL with many measure-y items anywhere on page
    for lst in soup.find_all(["ul", "ol"]):
        items = [clean_html(li.get_text()) for li in lst.find_all("li")]
        if not items:
            continue
        score = sum(1 for r in items if _has_measure(r) or NUMBERY_RE.search(r))
        if score >= max(2, len(items) // 3):
            lines.extend(items)

    return extract_unique_lines([x for x in lines if x])

def _extract_instruction_candidates(soup: BeautifulSoup) -> List[str]:
    lines: List[str] = []

    step_header = _find_first_matching_label(soup, STEP_HEADERS)
    if step_header:
        lines.extend(_collect_after(step_header, stop_labels=STOP_LABELS, max_nodes=260))

    # Prefer ordered lists with many items
    for ol in soup.find_all("ol"):
        items = [clean_html(li.get_text()) for li in ol.find_all("li")]
        if len(items) >= 2:
            lines.extend(items)

    # Some sites use <p> with numbered prefixes
    if not lines:
        paras = [clean_html(p.get_text()) for p in soup.find_all("p")]
        numbered = [p for p in paras if re.match(r"^\s*\d+[\.\)]\s+", p)]
        if len(numbered) >= 2:
            lines.extend(numbered)

    return extract_unique_lines([x for x in lines if x])

def parse_times_from_soup(soup: BeautifulSoup) -> Tuple[int, int]:
    txt = soup.get_text(separator="\n", strip=True)
    prep = 0
    cook = 0

    m_prep = re.search(r"זמן\s*הכנה\s*[:\-]\s*([^\n\r]+)", txt)
    if m_prep:
        prep = parse_time_value(m_prep.group(1))

    m_cook = re.search(r"זמן\s*(?:בישול|אפייה|בישול/אפייה|בישול\/אפייה)\s*[:\-]\s*([^\n\r]+)", txt)
    if m_cook:
        cook = parse_time_value(m_cook.group(1))

    if cook == 0:
        m_alt = re.search(r"(?:אופים|אפייה)\s*.*?(\d+\s*-\s*\d+|\d+)\s*(?:דק(?:ה|ות)?)", txt)
        if m_alt:
            cook = convert_to_int(m_alt.group(1))

    logger.info("[TIME] parsed: prep=%s cook=%s", prep, cook)
    return prep, cook

def extract_recipe_content(html_content: str) -> str:
    soup = BeautifulSoup(html_content, "html.parser")
    text = soup.get_text(separator="\n", strip=True)
    text = _limit_size(text, 120_000)
    return text

# =============================================================================
# LLM JSON repair helpers
# =============================================================================
def _strip_code_fences(text: str) -> str:
    s = text.strip()
    m = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", s, re.IGNORECASE)
    if m:
        return m.group(1).strip()
    if s.startswith("```"):
        s = s.split("```", 1)[1]
    if s.endswith("```"):
        s = s.rsplit("```", 1)[0]
    if s.lstrip().lower().startswith("json\n"):
        s = s.lstrip()[5:]
    return s.strip()

def _normalize_quotes(text: str) -> str:
    return (
        text.replace("\u201c", '"').replace("\u201d", '"')
        .replace("\u2018", "'").replace("\u2019", "'")
        .replace("“", '"').replace("”", '"').replace("‘", "'").replace("’", "'")
    )

def _remove_trailing_commas(s: str) -> str:
    return re.sub(r",(\s*[}\]])", r"\1", s)

def _quote_unquoted_keys(s: str) -> str:
    return re.sub(r'(?<=[{,])\s*([A-Za-z_][A-Za-z0-9_\-]*)\s*:', r'"\1":', s)

def _quote_unquoted_string_values(s: str) -> str:
    s = re.sub(
        r'(:\s*)(?!-?\d+(?:\.\d+)?\b)(?!true\b|false\b|null\b)(?!\"|\{|\[)([^,\}\]]+)',
        lambda m: m.group(1) + '"' + m.group(2).strip().replace('"', '\\"') + '"',
        s,
        flags=re.IGNORECASE,
    )
    s = re.sub(
        r'(?:(?<=\[)|(?<=,))\s*(?!-?\d+(?:\.\d+)?\b)(?!true\b|false\b|null\b)(?!\"|\{|\[)([^,\]\}]+)\s*(?=,|\])',
        lambda m: ' "' + m.group(1).strip().replace('"', '\\"') + '"',
        s,
        flags=re.IGNORECASE,
    )
    return s

def _collapse_whitespace(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()

async def extract_and_parse_llm_json(output: str) -> dict:
    s = _strip_code_fences(_normalize_quotes(output))
    s = _remove_trailing_commas(_quote_unquoted_keys(s))
    try:
        return json.loads(s)
    except json.JSONDecodeError:
        pass
    s2 = _quote_unquoted_string_values(s)
    s2 = _remove_trailing_commas(s2)
    try:
        return json.loads(s2)
    except json.JSONDecodeError:
        s3 = _collapse_whitespace(s2)
        s3 = _remove_trailing_commas(s3)
        return json.loads(s3)

# =============================================================================
# Normalization to RecipeModel
# =============================================================================
def normalize_recipe_fields(recipe_data: dict) -> RecipeModel:
    if not recipe_data.get("title") and recipe_data.get("recipeName"):
        recipe_data["title"] = recipe_data["recipeName"]

    recipe_data["prepTime"] = parse_time_value(recipe_data.get("prepTime", 0))
    recipe_data["cookTime"] = parse_time_value(recipe_data.get("cookTime", 0))
    if "servings" in recipe_data:
        recipe_data["servings"] = parse_servings(recipe_data["servings"])
    elif "recipeYield" in recipe_data:
        recipe_data["servings"] = parse_servings(recipe_data["recipeYield"])
    else:
        recipe_data["servings"] = 1

    ings = ensure_list(recipe_data.get("ingredients"))
    ings = [normalize_ingredient(x) for x in ings]
    ings = extract_unique_lines([x for x in ings if x])

    instr = recipe_data.get("instructions", [])
    if isinstance(instr, str):
        instr = [clean_html(x) for x in instr.split("\n") if clean_html(x)]
    else:
        instr = [clean_html(x) for x in ensure_list(instr) if clean_html(x)]
    instr = remove_exact_duplicates(instr)

    tags = recipe_data.get("tags", [])
    if isinstance(tags, str):
        tags = [clean_html(x) for x in tags.split(",") if clean_html(x)]
    else:
        tags = [clean_html(x) for x in ensure_list(tags) if clean_html(x)]

    model = RecipeModel(
        title=clean_html(recipe_data.get("title")),
        description=clean_html(recipe_data.get("description")),
        ingredients=ings,
        instructions=instr,
        prepTime=recipe_data.get("prepTime", 0),
        cookTime=recipe_data.get("cookTime", 0),
        servings=recipe_data.get("servings", 1),
        tags=tags,
        notes=clean_html(recipe_data.get("notes")),
        source=clean_html(recipe_data.get("source")),
        imageUrl=clean_html(recipe_data.get("imageUrl")),
    )
    logger.debug("[NORM] title='%s' ings=%d steps=%d prep=%d cook=%d",
                 model.title, len(model.ingredients), len(model.instructions), model.prepTime, model.cookTime)
    return model

# =============================================================================
# Fetchers
# =============================================================================
async def fetch_with_httpx(url: str) -> str:
    async with httpx.AsyncClient(timeout=HTTP_TIMEOUT, headers={"User-Agent": "RecipeKeeper/1.1"}) as client:
        r = await client.get(url, follow_redirects=True)
        r.raise_for_status()
        content = r.text
        kb = len(content.encode("utf-8", "ignore")) // 1024
        logger.info("[FETCH] httpx %d KB", kb)
        return _limit_size(content)

async def fetch_with_playwright(url: str) -> str:
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        try:
            context = await browser.new_context()
            page = await context.new_page()
            await page.goto(url, wait_until="load", timeout=PLAYWRIGHT_TIMEOUT_MS)
            content = await page.content()
            kb = len(content.encode("utf-8", "ignore")) // 1024
            logger.info("[FETCH] playwright %d KB", kb)
            return _limit_size(content)
        finally:
            await browser.close()

async def smart_fetch(url: str) -> str:
    try:
        html = await fetch_with_httpx(url)
        if len(html) < 5000:
            logger.info("[FETCH] httpx small; fallback to playwright")
            return await fetch_with_playwright(url)
        return html
    except Exception as e:
        logger.info("[FETCH] httpx failed (%s); fallback to playwright", e)
        return await fetch_with_playwright(url)

# =============================================================================
# OCR
# =============================================================================
def extract_text_from_image(image_bytes: bytes) -> str:
    try:
        image = Image.open(io.BytesIO(image_bytes))
        img = ImageOps.exif_transpose(image).convert("L")
        img = img.filter(ImageFilter.SHARPEN)
        img = img.point(lambda x: 0 if x < 160 else 255, mode="1")
        config = "--psm 6"
        text = pytesseract.image_to_string(img, lang="eng+heb", config=config)
        logger.debug("[OCR] extracted %d chars", len(text))
        return text
    except Exception as e:
        logger.error("[OCR] failure: %s", e, exc_info=True)
        raise APIError(f"OCR processing failed: {str(e)}")

# =============================================================================
# Prompts
# =============================================================================
def create_recipe_extraction_prompt(section_text: str) -> str:
    return (
        "את/ה מומחה/ית לחילוץ מתכונים. החזר/י אך ורק אובייקט JSON תקין יחיד (ללא טקסט נוסף), "
        "בדיוק עם המפתחות: title, description, ingredients, instructions, prepTime, cookTime, servings, tags, imageUrl, source.\n"
        "כללים: 1) החזר JSON בלבד; 2) numbers כמספרים (לא מחרוזות); 3) ללא פסיקים מיותרים; 4) ללא המצאות;\n"
        "- ingredients ו-instructions הן מערכים של מחרוזות נקיות (ללא מספור/תבליטים).\n"
        "- prepTime/cookTime בדקות שלמות (int).\n"
        "- servings מספר שלם.\n\n"
        "טקסט המתכון (האזור הרלוונטי):\n"
        f"{section_text}\n"
        "סיום."
    )

# =============================================================================
# FastAPI app
# =============================================================================
app = FastAPI(
    title="SpoonIt API",
    version="1.3.0",
    description="Generic recipe extraction via schema.org, DOM heuristics (Hebrew/English), and LLM fallback.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Disposition", "Access-Control-Allow-Origin"],
)

@app.exception_handler(APIError)
async def api_error_handler(request, exc: APIError):
    logger.error("APIError: %s | details=%s", exc.message, exc.details)
    return JSONResponse(status_code=exc.status_code, content={"error": exc.message, "details": exc.details})

@app.get("/")
async def root():
    return {"message": "Welcome to SpoonIt API", "docs": "/docs", "redoc": "/redoc"}

@app.get("/health")
async def health():
    return {"status": "ok"}

# -----------------------------------------------------------------------------
# Chat (Ollama) — unchanged behavior
# -----------------------------------------------------------------------------
@app.post("/chat")
async def chat(request: ChatRequest):
    sys_prompt = (
        "You are a helpful assistant. Please respond in Hebrew, clearly and well-formatted."
        if request.language.lower().startswith("he")
        else "You are a helpful assistant. Please respond in English, clearly and well-formatted."
    )
    prompt = f"{sys_prompt}\n\nUser: {request.message}\nAssistant:"
    payload = {"model": MODEL_NAME, "prompt": prompt, "stream": False}
    try:
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
            r = await client.post(OLLAMA_API_URL, json=payload)
            r.raise_for_status()
            data = r.json()
        return {"response": data.get("response", ""), "model": MODEL_NAME}
    except Exception as e:
        logger.error("[CHAT] error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail="Ollama request failed")

# -----------------------------------------------------------------------------
# Core extraction
# -----------------------------------------------------------------------------
def _build_filtered_section_for_llm(soup: BeautifulSoup) -> str:
    """Create a compact, *already-filtered* section for LLM fallback."""
    ing_candidates = _extract_ingredient_candidates(soup)
    ings = _filter_to_measured_ingredients(ing_candidates)

    step_candidates = _extract_instruction_candidates(soup)
    steps = _normalize_instruction_lines(step_candidates)

    parts: List[str] = []
    if ings:
        parts.append("רכיבים:\n" + "\n".join(ings))
    if steps:
        parts.append("אופן ההכנה:\n" + "\n".join(steps))
    return "\n\n".join(parts)

def _extract_generic_from_html(html: str) -> Optional[RecipeModel]:
    soup = BeautifulSoup(html, "html.parser")

    # title / description / image
    title = ""
    h1 = soup.find(["h1", "h2"])
    if h1:
        title = clean_html(h1.get_text())
    if not title:
        t = soup.find("title")
        title = clean_html(t.get_text()) if t else ""

    description = ""
    md = soup.find("meta", attrs={"property": "og:description"}) or soup.find("meta", attrs={"name": "description"})
    if md and md.get("content"):
        description = clean_html(md["content"])

    image_url = ""
    ogimg = soup.find("meta", attrs={"property": "og:image"})
    if ogimg and ogimg.get("content"):
        image_url = ogimg["content"]

    # ingredients / instructions
    ing_candidates = _extract_ingredient_candidates(soup)
    ingredients = _filter_to_measured_ingredients(ing_candidates)

    step_candidates = _extract_instruction_candidates(soup)
    instructions = _normalize_instruction_lines(step_candidates)

    prep, cook = parse_times_from_soup(soup)

    if (title and (len(ingredients) >= 2 or len(instructions) >= 2)) or (len(ingredients) >= 3 and len(instructions) >= 2):
        logger.info("[GENERIC] success | ings=%d steps=%d", len(ingredients), len(instructions))
        return RecipeModel(
            title=title,
            description=description,
            ingredients=ingredients,
            instructions=instructions,
            prepTime=prep,
            cookTime=cook,
            servings=1,
            tags=[],
            imageUrl=image_url,
        )
    logger.info("[GENERIC] not confident | ings=%d steps=%d", len(ingredients), len(instructions))
    return None

@app.post("/extract_recipe")
async def extract_recipe(req: RecipeExtractionRequest):
    url = req.url.strip()
    logger.info("[FLOW] extract_recipe START | url=%s", url)
    if not url.startswith("http"):
        raise HTTPException(status_code=400, detail="Invalid URL")

    try:
        html = await smart_fetch(url)
        soup = BeautifulSoup(html, "html.parser")

        # 1) schema.org
        model = parse_schema_org_recipe(html)
        if model and model.ingredients and model.instructions:
            if not model.source:
                model.source = url
            return model.model_dump()

        # 2) generic DOM heuristics (tables + lists; measured-only)
        model = _extract_generic_from_html(html)
        if model and (model.ingredients or model.instructions):
            if not model.source:
                model.source = url
            return model.model_dump()

        # 3) LLM fallback with filtered section
        section_text = _build_filtered_section_for_llm(soup)
        if len(section_text) < 80:
            section_text = extract_recipe_content(html)  # desperate fallback

        logger.info("[FOCUS] section len=%d", len(section_text))
        prompt = create_recipe_extraction_prompt(section_text)
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

        prep, cook = parse_times_from_soup(soup)
        recipe_dict.setdefault("prepTime", prep)
        recipe_dict.setdefault("cookTime", cook)
        recipe_dict.setdefault("source", url)

        recipe_model = normalize_recipe_fields(recipe_dict)
        if not recipe_model.title:
            recipe_model.title = "Recipe"
        logger.info("[FLOW] done via LLM | title='%s' ings=%d steps=%d prep=%d cook=%d",
                    recipe_model.title, len(recipe_model.ingredients), len(recipe_model.instructions),
                    recipe_model.prepTime, recipe_model.cookTime)
        return recipe_model.model_dump()

    except HTTPException:
        raise
    except Exception as e:
        logger.error("[FLOW] unexpected error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail="An unexpected error occurred during recipe extraction")

# -----------------------------------------------------------------------------
# Extract recipe from Base64 image
# -----------------------------------------------------------------------------
@app.post("/extract_recipe_from_image")
async def extract_recipe_from_image(req: ImageExtractionRequest):
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

# -----------------------------------------------------------------------------
# Upload recipe image (multipart)
# -----------------------------------------------------------------------------
@app.post("/upload_recipe_image")
async def upload_recipe_image(file: UploadFile = File(...)):
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

# -----------------------------------------------------------------------------
# Custom recipe generation
# -----------------------------------------------------------------------------
@app.post("/custom_recipe")
async def custom_recipe(req: CustomRecipeRequest):
    try:
        prompt = (
            "את/ה יוצר/ת מתכונים. בנה/י JSON יחיד ותקין בלבד.\n"
            f"מצרכים זמינים: {req.groceries}\n"
            f"תיאור בקשה: {req.description}\n\n"
            "החזר/י אך ורק אובייקט עם המפתחות: "
            "{title, description, ingredients, instructions, prepTime, cookTime, servings, tags, imageUrl, source}.\n"
            "חוקים: JSON תקין בלבד; ללא פסיקים מיותרים; מספרים לא במרכאות."
        )
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

# -----------------------------------------------------------------------------
# Simple image proxy (CORS bypass)
# -----------------------------------------------------------------------------
@app.get("/proxy_image")
async def proxy_image(url: str):
    try:
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT, follow_redirects=True) as client:
            r = await client.get(url)
            r.raise_for_status()
            content_type = r.headers.get("Content-Type", "image/jpeg")
            content = r.content
            
            # Check if the response is actually an image
            if not content_type or not content_type.startswith("image/"):
                logger.warning("[PROXY] Non-image content type: %s for URL: %s", content_type, url)
                # Try to find image URLs in the HTML content if it's a webpage
                if content_type and "text/html" in content_type:
                    from bs4 import BeautifulSoup
                    soup = BeautifulSoup(content, "html.parser")
                    img_tags = soup.find_all("img")
                    if img_tags:
                        # Try to find the first image with a valid src
                        for img in img_tags:
                            src = img.get("src")
                            if src and (src.startswith("http") or src.startswith("//")):
                                if src.startswith("//"):
                                    src = "https:" + src
                                logger.info("[PROXY] Found image in HTML: %s", src)
                                # Recursively call the proxy for the found image
                                return await proxy_image(src)
                
                raise HTTPException(status_code=400, detail="URL does not point to an image")
            
        return Response(
            content=content,
            media_type=content_type,
            headers={"Access-Control-Allow-Origin": "*", "Cache-Control": "public, max-age=86400"},
        )
    except Exception as e:
        logger.error("[PROXY] error: %s", e, exc_info=True)
        raise APIError(f"Failed to proxy image: {str(e)}", status_code=500)

# =============================================================================
# Entrypoint
# =============================================================================
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8002)
