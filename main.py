# main.py — SpoonIt Backend (updated)
# - Robust Gemini JSON handling (responseJsonSchema, multi-part concat, MAX_TOKENS handling)
# - Smaller, cleaner LLM context with Hebrew-aware cues
# - Graceful fallback (no 503 on LLM outage), partial heuristic return for Hebrew/EN sites
# - Minor logging hardening

from __future__ import annotations

import asyncio
import base64
import io
import json
import logging
import os
import re
from typing import Optional, Dict, Any, List, Iterable, Tuple

import httpx
import uvicorn
from bs4 import BeautifulSoup, NavigableString, Tag
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from PIL import Image, ImageOps, ImageFilter
from pydantic import BaseModel, Field

try:
    from playwright.async_api import async_playwright
    PLAYWRIGHT_AVAILABLE = True
except Exception:
    PLAYWRIGHT_AVAILABLE = False

import pytesseract
import pathlib
from io import StringIO

# =============================================================================
# .env loading (robust to encodings)
# =============================================================================
backend_dir = pathlib.Path(__file__).parent
env_path = backend_dir / ".env"

if env_path.exists():
    try:
        encodings = ["utf-8", "utf-8-sig", "utf-16", "utf-16-le", "utf-16-be", "latin-1"]
        content = None
        used_encoding = None
        for encoding in encodings:
            try:
                with open(env_path, "r", encoding=encoding) as f:
                    content = f.read()
                    used_encoding = encoding
                    break
            except (UnicodeDecodeError, UnicodeError):
                continue
        if content is None:
            load_dotenv(dotenv_path=env_path)
        else:
            if used_encoding != "utf-8":
                with open(env_path, "w", encoding="utf-8") as f:
                    f.write(content)
            load_dotenv(stream=StringIO(content))
    except Exception:
        load_dotenv(dotenv_path=env_path)
else:
    load_dotenv()

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
LLM_PROVIDER = os.getenv("LLM_PROVIDER", "gemini")  # "gemini" or "ollama"

# Ollama config (fallback)
OLLAMA_API_URL = os.getenv("OLLAMA_API_URL", "http://127.0.0.1:11434/api/generate")
MODEL_NAME = os.getenv("OLLAMA_MODEL", "gemma3:4b")

# Gemini config
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")

# HTTP / Fetch settings
HTTP_TIMEOUT = float(os.getenv("HTTP_TIMEOUT", 30.0))
PLAYWRIGHT_TIMEOUT_MS = int(os.getenv("PLAYWRIGHT_TIMEOUT_MS", 35000))
FETCH_MAX_BYTES = int(os.getenv("FETCH_MAX_BYTES", 2_500_000))  # safety cap ~2.5MB

# Common site-noise labels to strip
NAVIGATION_NOISE_KEYWORDS = [
    "#layout",
    "דף הבית",
    "מתכוניםמה אוכלים היום",
    "מתכונים הכי טעימים",
    "השף הלבן",
    "מפת אתר",
    "מדיניות פרטיות",
    "צור קשר",
    "Newsletter",
]

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
    image_data: str  # base64

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


def _contains_navigation_noise(text: str) -> bool:
    if not text:
        return False
    normalized = clean_html(text).strip()
    if not normalized:
        return True
    lowered = normalized.lower()
    for keyword in NAVIGATION_NOISE_KEYWORDS:
        if keyword.lower() in lowered:
            return True
    return False


def normalize_ingredient(item: Any) -> str:
    if item is None:
        return ""
    if isinstance(item, str):
        cleaned = clean_html(item).strip()
        cleaned = re.sub(r"^#[\w\-]+\s*", "", cleaned)
        if _contains_navigation_noise(cleaned):
            return ""
        if len(cleaned) > 120:
            return ""
        instruction_markers = [
            "הוראות", "אופן ההכנה", "כיצד", "מכינים", "מערבבים", "מוסיפים",
            "יוצקים", "מחממים", "אופים", "מקפיצים", "חותכים", "מפזרים",
            "instructions", "directions", "preparation", "method",
        ]
        cleaned_lower = cleaned.lower()
        if any(marker.lower() in cleaned_lower for marker in instruction_markers):
            return ""
        return cleaned
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
    s = clean_html(time_str).lower()
    if not s:
        return 0
    m = re.search(r"(\d+)\s*-\s*(\d+)\s*(?:דק(?:ה|ות)?|דק\b|min|minutes?)", s)
    if m:
        return max(int(m.group(1)), int(m.group(2)))
    mh = re.search(r"(\d+)\s*(?:שעה(?:ות)?|hr|hour|hours)", s)
    add_minutes = 0
    if mh:
        add_minutes += int(mh.group(1)) * 60
    elif "שעה" in s and not mh:
        add_minutes += 60
    mm = re.findall(r"(\d+)\s*(?:דק(?:ה|ות)?|דק\b|min|minutes?)", s)
    if mm:
        add_minutes += int(mm[0])
    if add_minutes:
        return add_minutes
    m2 = re.search(r"(\d+)\s*(?:דק(?:ה|ות)?|דק\b|min|minutes?)", s)
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
        if any(lbl.lower() in text.lower() for lbl in stop_labels):
            break
        if sib.name in ("ul", "ol", "table"):
            lines.extend(_text_lines_from_tag(sib))
            continue
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
    if MEASURE_RE.search(s):
        return True
    measurement_keywords = ["כף", "כפית", "קורט", "קמצוץ", "חופן", "מעט"]
    lowered = s.lower()
    return any(keyword in lowered for keyword in measurement_keywords)


def _stitch_broken_ingredient_lines(lines: List[str]) -> List[str]:
    out: List[str] = []
    for ln in lines:
        ln = clean_html(ln)
        if not ln:
            continue
        if _contains_navigation_noise(ln):
            continue
        if out and not _has_measure(out[-1]) and (_has_measure(ln) or ln.startswith("(") or ln.startswith("או ")):
            out[-1] = (out[-1] + " " + ln).strip()
        elif out and not _has_measure(out[-1]) and re.match(r"^\d", ln):
            out[-1] = (out[-1] + " " + ln).strip()
        else:
            out.append(ln)
    return out


def _looks_like_instruction_paragraph(text: str) -> bool:
    s = clean_html(text).strip()
    if not s:
        return False
    if len(s) > 120:
        return True
    step_markers = re.findall(r"(?:(?<=\\s)|^)(?:0?\\d{1,2})[\\.)]", s)
    if len(step_markers) >= 2:
        return True
    if sum(ch in s for ch in ".!?") >= 3:
        return True
    cues = [
        "הוראות", "אופן ההכנה", "כיצד", "מכינים", "מערבבים", "מוסיפים",
        "יוצקים", "מחממים", "אופים", "מקפיצים", "חותכים", "מפזרים",
        "טיימר", "º", "instructions", "directions", "preparation", "method",
    ]
    low = s.lower()
    return any(c.lower() in low for c in cues)


def _filter_to_measured_ingredients(lines: List[str]) -> List[str]:
    stitched = _stitch_broken_ingredient_lines(lines)
    measured = [
        x for x in stitched
        if (_has_measure(x) or NUMBERY_RE.search(x)) and not _looks_like_instruction_paragraph(x)
    ]
    if len(measured) < 2:
        measured = [
            x for x in stitched
            if (_has_measure(x) or "לפי הטעם" in x or "קורט" in x)
            and not _looks_like_instruction_paragraph(x)
        ]
    measured = [re.sub(r"\s{2,}", " ", x).strip("•-—· ").strip() for x in measured]
    return extract_unique_lines([x for x in measured if len(x) > 1])


def _normalize_instruction_lines(lines: List[str]) -> List[str]:
    li_like: List[str] = []
    for raw in lines:
        if _contains_navigation_noise(raw):
            continue
        m = re.match(r"^\s*(\d+)[\.\)]?\s*(.*)$", clean_html(raw))
        if m:
            li_like.append(f"{m.group(1)}. {m.group(2).strip()}")
        else:
            li_like.append(clean_html(raw))
    steps: List[str] = []
    buf = ""
    for ln in li_like:
        if not ln:
            continue
        m = re.match(r"^\s*(\d+)[\.\)]\s+(.*)$", ln)
        if m:
            if buf:
                steps.append(buf.strip())
                buf = ""
            buf = m.group(2).strip()
        else:
            if any(x in ln for x in ("סוג המנה", "דרגת קושי", "זמן הכנה", "כשרות")):
                continue
            if buf:
                sep = " " if not ln.startswith("(") else " "
                buf += sep + ln
            else:
                buf = ln
    if buf:
        steps.append(buf.strip())
    if not steps:
        for ln in lines:
            t = clean_html(ln)
            if len(t) > 2 and not _contains_navigation_noise(t):
                steps.append(t)
    steps = [re.sub(r"\s{2,}", " ", s).strip("•-—· ").strip() for s in steps if not _contains_navigation_noise(s)]
    return remove_exact_duplicates([s for s in steps if len(s) > 2 and not _contains_navigation_noise(s)])

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
                if not ings:
                    ing_candidates = _extract_ingredient_candidates(soup)
                    ings = _filter_to_measured_ingredients(ing_candidates)
                if not instr:
                    step_candidates = _extract_instruction_candidates(soup)
                    instr = _normalize_instruction_lines(step_candidates)
                def _duration_to_min(v: str) -> int:
                    v = v or ""
                    m = re.search(r"PT(?:(\d+)H)?(?:(\d+)M)?", v, re.I)
                    if m:
                        return (int(m.group(1) or 0) * 60) + int(m.group(2) or 0)
                    return parse_time_value(v)
                prep = _duration_to_min(safe_strip(obj.get("prepTime")))
                cook = _duration_to_min(safe_strip(obj.get("cookTime")))
                servings = parse_servings(obj.get("recipeYield"))
                if prep == 0 or servings == 1:
                    prep_from_html, cook_from_html = parse_times_from_soup(soup)
                    if prep == 0 and prep_from_html > 0:
                        prep = prep_from_html
                    if cook == 0 and cook_from_html > 0:
                        cook = cook_from_html
                if servings == 1:
                    servings_from_html = _extract_servings_from_soup(soup)
                    if servings_from_html > 1:
                        servings = servings_from_html
                if not image_url:
                    image_from_html = _extract_recipe_image_from_soup(soup)
                    if image_from_html:
                        image_url = image_from_html
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
                logger.info("[SCHEMA] success | title='%s' ings=%d steps=%d prep=%d cook=%d servings=%d",
                            model.title or "", len(model.ingredients), len(model.instructions),
                            model.prepTime, model.cookTime, model.servings)
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
    ing_header = _find_first_matching_label(soup, ING_HEADERS)
    if ing_header:
        lines.extend(_collect_after(ing_header, stop_labels=STOP_LABELS, max_nodes=220))
    for tbl in soup.find_all("table"):
        rows = _text_lines_from_tag(tbl)
        score = sum(1 for r in rows if _has_measure(r) or NUMBERY_RE.search(r))
        if score >= 2:
            lines.extend(rows)
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
    for ol in soup.find_all("ol"):
        items = [clean_html(li.get_text()) for li in ol.find_all("li")]
        if len(items) >= 2:
            lines.extend(items)
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
    if prep == 0:
        m_prep_alt = re.search(r"(\d+)\s*דק\b", txt)
        if m_prep_alt:
            prep = int(m_prep_alt.group(1))
    m_cook = re.search(r"זמן\s*(?:בישול|אפייה|בישול/אפייה|בישול\/אפייה)\s*[:\-]\s*([^\n\r]+)", txt)
    if m_cook:
        cook = parse_time_value(m_cook.group(1))
    if cook == 0:
        m_alt = re.search(r"(?:אופים|אפייה)\s*.*?(\d+\s*-\s*\d+|\d+)\s*(?:דק(?:ה|ות)?|דק\b)", txt)
        if m_alt:
            cook = convert_to_int(m_alt.group(1))
    logger.info("[TIME] parsed: prep=%s cook=%s", prep, cook)
    return prep, cook


def _extract_servings_from_soup(soup: BeautifulSoup) -> int:
    txt = soup.get_text(separator="\n", strip=True)
    patterns = [
        r"ל\s*(\d+)\s*מנות",
        r"(\d+)\s*מנות",
        r"המרכיבים\s*ל\s*(\d+)\s*מנות",
        r"serves?\s*(\d+)",
        r"(\d+)\s*servings?",
    ]
    for pattern in patterns:
        m = re.search(pattern, txt, re.IGNORECASE)
        if m:
            servings = int(m.group(1))
            if servings > 0:
                return servings
    return 1


def _extract_recipe_image_from_soup(soup: BeautifulSoup) -> str:
    candidates = []
    ogimg = soup.find("meta", attrs={"property": "og:image"})
    if ogimg and ogimg.get("content"):
        img_url = ogimg["content"]
        if img_url and img_url.startswith("http"):
            candidates.append({"url": img_url, "score": 100, "source": "og:image"})
    twitter_img = soup.find("meta", attrs={"name": "twitter:image"})
    if twitter_img and twitter_img.get("content"):
        img_url = twitter_img["content"]
        if img_url and img_url.startswith("http"):
            candidates.append({"url": img_url, "score": 90, "source": "twitter:image"})
    for img in soup.find_all("img"):
        src = img.get("src") or img.get("data-src") or img.get("data-lazy-src")
        if not src:
            continue
        if src.startswith("//"):
            src = "https:" + src
        elif not src.startswith("http"):
            continue
        if any(skip in src.lower() for skip in ["icon", "logo", "avatar", "button", "banner", "ad-", "ads-"]):
            continue
        score = 50
        alt = (img.get("alt") or "").lower()
        if alt:
            recipe_keywords = ["recipe", "מתכון", "food", "dish", "meal", "אוכל", "מנה", "תבשיל"]
            if any(kw in alt for kw in recipe_keywords):
                score += 30
        classes = " ".join(img.get("class", [])).lower()
        if any(kw in classes for kw in ["recipe", "hero", "featured", "main", "primary"]):
            score += 20
        parent_tags = [p.name for p in img.parents]
        if "article" in parent_tags or "main" in parent_tags:
            score += 15
        width = img.get("width")
        height = img.get("height")
        if width and height:
            try:
                w, h = int(width), int(height)
                if w >= 600 or h >= 400:
                    score += 10
            except:
                pass
        candidates.append({"url": src, "score": score, "source": f"img[alt='{alt[:30]}...']"})
    if candidates:
        candidates.sort(key=lambda x: x["score"], reverse=True)
        best = candidates[0]
        logger.info("[IMAGE] Selected image: %s (score: %d, source: %s)", best["url"][:80], best["score"], best["source"])
        return best["url"]
    return ""


def extract_recipe_content(html_content: str) -> str:
    soup = BeautifulSoup(html_content, "html.parser")
    text = soup.get_text(separator="\n", strip=True)
    text = _limit_size(text, 120_000)
    return text


def _extract_hebrew_sections_from_text(text: str) -> Tuple[List[str], List[str]]:
    s = _collapse_whitespace(text.replace("\r", "\n"))
    s = re.sub(r"(מצרכים[^\n]*:)", r"\n\1\n", s)
    s = re.sub(r"(למילוי[^\n]*:)", r"\n\1\n", s)
    s = re.sub(r"(לציפוי[^\n]*:)", r"\n\1\n", s)
    s = re.sub(r"(אופן ההכנה[^\n]*:)", r"\n\1\n", s)
    lines = [ln.strip() for ln in s.split("\n") if ln.strip()]
    ingredients: List[str] = []
    instructions: List[str] = []
    current = None
    INGS_HEADERS = ["מצרכים", "למילוי", "לציפוי"]
    STEPS_HEADERS = ["אופן ההכנה", "הוראות הכנה", "אופן ההכנה:"]

    def is_header(line: str) -> bool:
        plain = line.rstrip(":")
        return plain in INGS_HEADERS or plain in STEPS_HEADERS

    for ln in lines:
        key = ln.rstrip(":")
        if key in INGS_HEADERS:
            current = 'ings'
            continue
        if key in STEPS_HEADERS:
            current = 'steps'
            continue
        if any(tok in ln for tok in ["תגובות", "צילום", "לחצו כאן", "ספטמבר", "אוקטובר", "נובמבר"]):
            continue
        if current == 'ings':
            if len(ln) > 180:
                continue
            if not is_header(ln):
                ingredients.append(clean_html(ln))
        elif current == 'steps':
            if not is_header(ln):
                instructions.append(clean_html(ln))
    ingredients = [ing for ing in ingredients if not _looks_like_instruction_paragraph(ing)]
    return (ingredients, instructions)

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
            .replace("“", '"').replace("”", '"').replace("'", "'").replace("'", "'")
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
    async with httpx.AsyncClient(timeout=HTTP_TIMEOUT, headers={"User-Agent": "RecipeKeeper/1.2"}) as client:
        r = await client.get(url, follow_redirects=True)
        r.raise_for_status()
        content = r.text
        kb = len(content.encode("utf-8", "ignore")) // 1024
        logger.info("[FETCH] httpx %d KB", kb)
        return _limit_size(content)


async def fetch_with_playwright(url: str) -> str:
    if not PLAYWRIGHT_AVAILABLE:
        raise RuntimeError("Playwright not available in environment")
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        try:
            context = await browser.new_context()
            page = await context.new_page()
            strategies = [("domcontentloaded", 15000), ("load", PLAYWRIGHT_TIMEOUT_MS)]
            content = None
            last_error = None
            for wait_until, timeout in strategies:
                try:
                    await page.goto(url, wait_until=wait_until, timeout=timeout)
                    await page.wait_for_timeout(2000)
                    content = await page.content()
                    kb = len(content.encode("utf-8", "ignore")) // 1024
                    logger.info("[FETCH] playwright %d KB (strategy: %s)", kb, wait_until)
                    if kb >= 5:
                        break
                    else:
                        logger.warning("[FETCH] Small content with '%s', trying next strategy", wait_until)
                except Exception as e:
                    last_error = e
                    logger.warning("[FETCH] Strategy '%s' failed: %s", wait_until, str(e)[:100])
                    continue
            if not content or len(content) < 500:
                if last_error:
                    raise last_error
                raise Exception("Failed to fetch content with all strategies")
            return _limit_size(content)
        finally:
            await browser.close()


async def smart_fetch(url: str) -> str:
    try:
        html = await fetch_with_httpx(url)
        if len(html) < 5000 and PLAYWRIGHT_AVAILABLE:
            logger.info("[FETCH] httpx small; fallback to playwright")
            return await fetch_with_playwright(url)
        return html
    except Exception as e:
        logger.info("[FETCH] httpx failed (%s); fallback to playwright", e)
        if PLAYWRIGHT_AVAILABLE:
            return await fetch_with_playwright(url)
        raise

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

def create_recipe_extraction_prompt(section_text: str) -> Tuple[str, str]:
    system_prompt = (
        "You are an expert recipe extraction assistant. The content may be in Hebrew or English. "
        "Extract recipe information and return ONLY a valid JSON object with these exact keys: "
        "title, description, ingredients, instructions, prepTime, cookTime, servings, tags, imageUrl, source. "
        "Rules: 1) Return JSON only (no markdown, no code blocks); 2) Numbers as integers (not strings); "
        "3) No trailing commas; 4) ingredients and instructions are arrays of clean strings (no numbering/bullets); "
        "5) prepTime/cookTime in whole minutes (integers); 6) servings as integer; "
        "7) CRITICAL: ingredients array must contain ONLY food items/measurements, NOT preparation instructions or navigation text; "
        "8) Remove any text like 'הוראות הכנה', '#layout', menus, or user comments; "
        "9) instructions array must contain ONLY cooking steps; 10) If some fields are not explicitly stated, infer reasonable values, but do not invent. "
        "11) Prefer Hebrew labels (e.g., 'רכיבים', 'אופן ההכנה') when present; otherwise, use context. "
        "12) MANDATORY: You MUST extract at least 2 ingredients and 2 instructions. "
        "13) Do NOT translate content – preserve original language of ingredients/instructions."
    )
    user_prompt = (
        "Extract the recipe from this text. The text may include a compact section followed by broader page text.\n\n"
        f"{section_text}\n\n"
        "IMPORTANT: Identify ingredients and instructions. Look for:\n"
        "- Ingredients: lines with measurements (e.g., numbers, cups, spoons, grams, כוס, כפית, גרם) and food items\n"
        "- Instructions: numbered steps or paragraphs describing how to prepare/cook the recipe\n"
        "Return only the JSON object with the required fields."
    )
    return system_prompt, user_prompt

# =============================================================================
# Gemini & Ollama LLM calls (updated Gemini handling)
# =============================================================================

def _extract_all_text_parts_from_candidate(candidate: dict) -> str:
    content_text = ""
    if not candidate:
        return content_text
    content_obj = candidate.get("content")
    def collect(parts):
        nonlocal content_text
        if isinstance(parts, list):
            for part in parts:
                if isinstance(part, dict):
                    if isinstance(part.get("text"), str):
                        content_text += part["text"]
                    elif isinstance(part.get("inline_data"), dict):
                        try:
                            content_text += json.dumps(part["inline_data"])  # last resort
                        except Exception:
                            pass
    if isinstance(content_obj, dict):
        collect(content_obj.get("parts"))
    elif isinstance(content_obj, list):
        for item in content_obj:
            if isinstance(item, dict):
                collect(item.get("parts"))
    return content_text
    content_obj = candidate.get("content")
    if isinstance(content_obj, dict):
        parts = content_obj.get("parts")
        if isinstance(parts, list):
            for part in parts:
                if isinstance(part, dict):
                    if "text" in part and isinstance(part["text"], str):
                        content_text += part["text"]
                    # Some responses may embed JSON objects directly in parts
                    elif "inline_data" in part and isinstance(part["inline_data"], dict):
                        try:
                            # Not typical for JSON text, but keep as last resort
                            content_text += json.dumps(part["inline_data"])  # stringify
                        except Exception:
                            pass
    elif isinstance(content_obj, list):
        for item in content_obj:
            if isinstance(item, dict):
                parts = item.get("parts")
                if isinstance(parts, list):
                    for part in parts:
                        if isinstance(part, dict) and "text" in part and isinstance(part["text"], str):
                            content_text += part["text"]
    return content_text


async def call_gemini_llm(prompt: str, system_prompt: str = None) -> str:
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY not configured")

    base_instruction = "IMPORTANT: Return ONLY valid JSON, no markdown, no code blocks, just the raw JSON object."
    user_prompt = f"{prompt}

{base_instruction}"
    combined_prompt = f"{system_prompt}

{user_prompt}" if system_prompt else user_prompt

    def build_payload(text: str, json_schema: bool) -> dict:
        generation_config: Dict[str, Any] = {"temperature": 0, "maxOutputTokens": 2000}
        if json_schema:
            generation_config["responseMimeType"] = "application/json"
            generation_config["responseJsonSchema"] = {
                "type": "object",
                "properties": {
                    "title": {"type": "string"},
                    "ingredients": {"type": "array", "items": {"type": "string"}},
                    "instructions": {"type": "array", "items": {"type": "string"}},
                    "description": {"type": "string"},
                    "prepTime": {"type": "integer"},
                    "cookTime": {"type": "integer"},
                    "servings": {"type": "integer"},
                    "tags": {"type": "array", "items": {"type": "string"}},
                    "imageUrl": {"type": "string"},
                    "source": {"type": "string"},
                },
                "required": ["title", "ingredients", "instructions"],
            }
        return {
            "contents": [{"parts": [{"text": text}]}],
            "generationConfig": generation_config,
        }

    async def try_once(use_schema: bool, text: str) -> Optional[str]:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent"
        payload = build_payload(text, use_schema)
        headers = {"x-goog-api-key": GEMINI_API_KEY, "Content-Type": "application/json"}
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
            r = await client.post(url, json=payload, headers=headers)
            r.raise_for_status()
            data = r.json()
        if "candidates" in data and data["candidates"]:
            candidate = data["candidates"][0]
            content_text = _extract_all_text_parts_from_candidate(candidate)
            finish_reason = candidate.get("finishReason")
            if content_text:
                return content_text
            if finish_reason == "MAX_TOKENS":
                return None  # signal to retry with smaller prompt
        return None

    # First try: schema on, full combined prompt
    out = await try_once(True, combined_prompt)
    if out:
        return out
    # Second try: schema off (sometimes helps)
    out = await try_once(False, combined_prompt)
    if out:
        return out
    # Third try: shrink prompt to essential fields only (title/ings/steps)
    minimal_user = re.sub(r"(?s)description.*?tags, imageUrl, source\.", "", prompt)
    minimal_prompt = (
        "Return ONLY JSON with keys: title, ingredients, instructions. "
        "Do not include any other keys. Ingredients/instructions must be arrays. "
        "No markdown/code fences.

" + minimal_user
    )
    out = await try_once(True, minimal_prompt)
    if out:
        return out

    raise HTTPException(status_code=500, detail="Gemini request failed after retries")


async def call_ollama_llm(prompt: str) -> str:
    payload = {
        "model": MODEL_NAME,
        "prompt": prompt,
        "stream": False,
        "format": "json",
        "options": {"temperature": 0, "num_ctx": 4096, "top_k": 40, "top_p": 0.9},
    }
    try:
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
            r = await client.post(OLLAMA_API_URL, json=payload)
            r.raise_for_status()
            data = r.json()
            return data.get("response", "")
    except httpx.ConnectError:
        logger.error("[OLLAMA] Connection failed - Ollama is not running. Please start Ollama or use Gemini API.")
        raise HTTPException(
            status_code=503,
            detail="Ollama service is not available. Please start Ollama locally or configure Gemini API.",
        )
    except Exception as e:
        logger.error("[OLLAMA] error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail=f"Ollama request failed: {str(e)}")

# =============================================================================
# FastAPI app
# =============================================================================

app = FastAPI(
    title="SpoonIt API",
    version="1.4.0",
    description="Recipe extraction via schema.org, DOM heuristics (Hebrew/English), and LLM fallback (Gemini/Ollama).",
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
# Core extraction helpers & routes
# -----------------------------------------------------------------------------

def _build_filtered_section_for_llm(soup: BeautifulSoup) -> str:
    ing_candidates = _extract_ingredient_candidates(soup)
    ings = _filter_to_measured_ingredients(ing_candidates)
    step_candidates = _extract_instruction_candidates(soup)
    steps = _normalize_instruction_lines(step_candidates)
    parts: List[str] = []
    if ings:
        parts.append("רכיבים:\n" + "\n".join(ings))
    if steps:
        parts.append("אופן ההכנה:\n" + "\n".join(steps))
    filtered = "\n\n".join(parts).strip()
    if len(filtered) < 300 or (len(ings) < 3 and len(steps) < 3):
        page_text = soup.get_text(separator="\n", strip=True)
        noise_words = ["תגובות", "Comments", "שיתוף", "share this", "עוד מתכונים"]
        cleaned_lines: List[str] = []
        for line in page_text.splitlines():
            if any(noise in line for noise in noise_words):
                break
            if len(line.strip()) < 2 or line.strip().startswith(("©", "#", "http")):
                continue
            cleaned_lines.append(line.strip())
        page_text = " ".join(cleaned_lines)
        page_text = _limit_size(page_text, 4000)
        if filtered:
            filtered = f"{filtered}\n\nטקסט דף נוסף:\n{page_text}"
        else:
            filtered = page_text
    return filtered


def _extract_generic_from_html(html: str) -> Optional[RecipeModel]:
    soup = BeautifulSoup(html, "html.parser")

    def _clean_title(raw_title: str, url: str) -> str:
        t = clean_html(raw_title)
        if not t:
            return ""
        # Prefer left-most before separators
        for sep in [" - ", " | ", " — ", " – "]:
            if sep in t:
                t = t.split(sep)[0].strip()
                break
        # Remove site/brand tokens
        host = ""
        try:
            host = re.sub(r"^www\.", "", re.sub(r"https?://", "", url)).split("/")[0]
        except Exception:
            pass
        site_name = ""
        og_site = soup.find("meta", attrs={"property": "og:site_name"})
        if og_site and og_site.get("content"):
            site_name = clean_html(og_site["content"])
        for token in filter(None, [host, site_name]):
            token_plain = token.split(".")[0]
            t = re.sub(rf"{re.escape(token_plain)}", "", t, flags=re.IGNORECASE).strip()
        return t.strip(" -|—–\u00a0")

    # title preference: og:title > h1/h2 > <title>
    title_tag = soup.find("meta", attrs={"property": "og:title"})
    title = clean_html(title_tag["content"]) if title_tag and title_tag.get("content") else ""
    if not title:
        h1 = soup.find(["h1", "h2"]) 
        if h1:
            title = clean_html(h1.get_text())
    if not title:
        t = soup.find("title")
        title = clean_html(t.get_text()) if t else ""
    title = _clean_title(title, html)

    description = ""
    md = soup.find("meta", attrs={"property": "og:description"}) or soup.find("meta", attrs={"name": "description"})
    if md and md.get("content"):
        description = clean_html(md["content"]) 

    image_url = _extract_recipe_image_from_soup(soup)

    def _extract_by_classes(root: BeautifulSoup, classes: List[str]) -> List[str]:
        results: List[str] = []
        for cls in classes:
            for node in root.select(f".{cls} li, .{cls} p"):
                txt = clean_html(node.get_text())
                if txt:
                    results.append(txt)
        return results

    ing_candidates = _extract_ingredient_candidates(soup)
    # Extend with common WP recipe plugins classes (he/en)
    ing_candidates += _extract_by_classes(
        soup,
        [
            "ingredients", "wprm-recipe-ingredients", "tasty-recipes-ingredients", "trx-ingredients",
            "מצרכים", "מרכיבים",
        ],
    )
    ingredients = _filter_to_measured_ingredients(ing_candidates)

    step_candidates = _extract_instruction_candidates(soup)
    step_candidates += _extract_by_classes(
        soup,
        [
            "instructions", "wprm-recipe-instructions", "tasty-recipes-instructions", "trx-instructions",
            "אופן-ההכנה", "אופן_ההכנה", "הוראות- הכנה", "הוראות-הכנה",
        ],
    )
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
        # 2) DOM heuristics
        model = _extract_generic_from_html(html)
        if model and (model.ingredients or model.instructions):
            if not model.source:
                model.source = url
            return model.model_dump()
        # 3) LLM fallback
        section_text = _build_filtered_section_for_llm(soup)
        page_text = extract_recipe_content(html)
        if len(section_text) < 80:
            section_text = page_text
        logger.info("[FOCUS] section len=%d", len(section_text))
        if len(section_text) < 100:
            logger.warning("[FLOW] Very little content found. Possibly not a recipe page.")
            raise HTTPException(status_code=400, detail="Could not find recipe content on the page.")
        system_prompt, user_prompt = create_recipe_extraction_prompt(section_text)
        output: Optional[str] = None
        try:
            if LLM_PROVIDER == "gemini":
                logger.info("[LLM] Using Gemini API")
                try:
                    output = await call_gemini_llm(user_prompt, system_prompt)
                except Exception as e:
                    logger.warning("[LLM] Gemini failed: %s", e)
                    try:
                        combined_prompt = f"{system_prompt}\n\n{user_prompt}"
                        output = await call_ollama_llm(combined_prompt)
                    except Exception as ollama_err:
                        logger.error("[LLM] Ollama fallback failed: %s", ollama_err)
                        output = None
            else:
                logger.info("[LLM] Using Ollama")
                combined_prompt = f"{system_prompt}\n\n{user_prompt}"
                output = await call_ollama_llm(combined_prompt)
        except Exception as e:
            logger.error("[FLOW] LLM request error: %s", e, exc_info=True)
            output = None
        if output:
            try:
                try:
                    recipe_dict = json.loads(output)
                except json.JSONDecodeError:
                    recipe_dict = await extract_and_parse_llm_json(output)
                prep, cook = parse_times_from_soup(soup)
                recipe_dict.setdefault("prepTime", prep)
                recipe_dict.setdefault("cookTime", cook)
                recipe_dict.setdefault("source", url)
                recipe_model = normalize_recipe_fields(recipe_dict)
                if not recipe_model.title:
                    recipe_model.title = "Recipe"
                logger.info(
                    "[FLOW] done via LLM | title='%s' ings=%d steps=%d prep=%d cook=%d",
                    recipe_model.title, len(recipe_model.ingredients), len(recipe_model.instructions),
                    recipe_model.prepTime, recipe_model.cookTime,
                )
                if (not recipe_model.ingredients) or (not recipe_model.instructions):
                    heb_ings, heb_steps = _extract_hebrew_sections_from_text(page_text)
                    if not recipe_model.ingredients and heb_ings:
                        recipe_model.ingredients = heb_ings
                        logger.info("[FLOW] Backfilled %d ingredients from Hebrew parser", len(heb_ings))
                    if not recipe_model.instructions and heb_steps:
                        recipe_model.instructions = heb_steps
                        logger.info("[FLOW] Backfilled %d instructions from Hebrew parser", len(heb_steps))
                if not recipe_model.ingredients and not recipe_model.instructions:
                    logger.warning("[FLOW] Empty recipe after LLM")
                    # fallthrough to heuristic-only partial
                else:
                    return recipe_model.model_dump()
            except Exception as e:
                logger.warning("[FLOW] Failed to parse LLM output, will try heuristic fallback: %s", e)
        # Heuristic partial fallback (no 503)
        logger.info("[FALLBACK] Using heuristic extraction for partial data")
        title = soup.find(["h1", "h2"]) 
        title_text = clean_html(title.get_text()) if title else ""
        if not title_text:
            t_tag = soup.find("title")
            title_text = clean_html(t_tag.get_text()) if t_tag else ""
        desc_tag = soup.find("meta", {"property": "og:description"}) or soup.find("meta", {"name": "description"})
        description = clean_html(desc_tag["content"]) if desc_tag and desc_tag.get("content") else ""
        ing_candidates = _extract_ingredient_candidates(soup)
        ingredients = _filter_to_measured_ingredients(ing_candidates)
        step_candidates = _extract_instruction_candidates(soup)
        instructions = _normalize_instruction_lines(step_candidates)
        if not ingredients and not instructions:
            heb_ings, heb_steps = _extract_hebrew_sections_from_text(page_text)
            if heb_ings:
                ingredients = [clean_html(x) for x in heb_ings]
            if heb_steps:
                instructions = [clean_html(x) for x in heb_steps]
        if ingredients or instructions or title_text or description:
            recipe_model = RecipeModel(
                title=title_text or "Recipe",
                description=description,
                ingredients=ingredients or [],
                instructions=instructions or [],
                prepTime=0,
                cookTime=0,
                servings=1,
                tags=[],
                imageUrl=_extract_recipe_image_from_soup(soup),
                source=url,
            )
            logger.warning(
                "[FALLBACK] LLM failed; returning partial data (ings=%d, steps=%d)",
                len(recipe_model.ingredients), len(recipe_model.instructions),
            )
            return recipe_model.model_dump()
        raise HTTPException(status_code=400, detail="Could not extract recipe content via LLM or heuristics.")
    except HTTPException:
        raise
    except Exception as e:
        logger.error("[FLOW] unexpected error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail="An unexpected error occurred during recipe extraction")


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
        system_prompt, user_prompt = create_recipe_extraction_prompt(text)
        output: Optional[str] = None
        try:
            if LLM_PROVIDER == "gemini":
                logger.info("[LLM] Using Gemini API for image extraction")
                try:
                    output = await call_gemini_llm(user_prompt, system_prompt)
                except Exception as e:
                    logger.warning("[LLM] Gemini failed, falling back to Ollama: %s", e)
                    combined_prompt = f"{system_prompt}\n\n{user_prompt}"
                    output = await call_ollama_llm(combined_prompt)
            else:
                logger.info("[LLM] Using Ollama for image extraction")
                combined_prompt = f"{system_prompt}\n\n{user_prompt}"
                output = await call_ollama_llm(combined_prompt)
        except Exception as e:
            logger.error("[IMG] LLM error: %s", e)
            output = None
        if output:
            try:
                try:
                    recipe_dict = json.loads(output)
                except json.JSONDecodeError:
                    recipe_dict = await extract_and_parse_llm_json(output)
                recipe_model = normalize_recipe_fields(recipe_dict)
                return recipe_model.model_dump()
            except Exception:
                logger.warning("[IMG] Failed to parse LLM output; returning heuristic text only")
        # Heuristic-only fallback from OCR text
        ings, steps = _extract_hebrew_sections_from_text(text)
        if ings or steps:
            model = RecipeModel(title="Recipe", ingredients=ings, instructions=steps)
            return model.model_dump()
        raise HTTPException(status_code=500, detail="Error processing image: could not parse recipe")
    except HTTPException:
        raise
    except Exception as e:
        logger.error("[IMG] error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error processing image: {str(e)}")


@app.post("/upload_recipe_image")
async def upload_recipe_image(file: UploadFile = File(...)):
    try:
        contents = await file.read()
        text = extract_text_from_image(contents)
        if not text or len(text) < 40:
            raise HTTPException(status_code=400, detail="Not enough text extracted from image")
        system_prompt, user_prompt = create_recipe_extraction_prompt(text)
        output: Optional[str] = None
        try:
            if LLM_PROVIDER == "gemini":
                logger.info("[LLM] Using Gemini API for image extraction")
                try:
                    output = await call_gemini_llm(user_prompt, system_prompt)
                except Exception as e:
                    logger.warning("[LLM] Gemini failed, falling back to Ollama: %s", e)
                    combined_prompt = f"{system_prompt}\n\n{user_prompt}"
                    output = await call_ollama_llm(combined_prompt)
            else:
                logger.info("[LLM] Using Ollama for image extraction")
                combined_prompt = f"{system_prompt}\n\n{user_prompt}"
                output = await call_ollama_llm(combined_prompt)
        except Exception as e:
            logger.error("[UPLOAD] LLM error: %s", e)
            output = None
        if output:
            try:
                try:
                    recipe_dict = json.loads(output)
                except json.JSONDecodeError:
                    recipe_dict = await extract_and_parse_llm_json(output)
                recipe_model = normalize_recipe_fields(recipe_dict)
                return recipe_model.model_dump()
            except Exception:
                logger.warning("[UPLOAD] Failed to parse LLM output; falling back heuristics")
        ings, steps = _extract_hebrew_sections_from_text(text)
        if ings or steps:
            model = RecipeModel(title="Recipe", ingredients=ings, instructions=steps)
            return model.model_dump()
        raise HTTPException(status_code=500, detail="Error processing uploaded image: could not parse recipe")
    except HTTPException:
        raise
    except Exception as e:
        logger.error("[UPLOAD] error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error processing uploaded image: {str(e)}")


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


@app.get("/proxy_image")
async def proxy_image(url: str):
    try:
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT, follow_redirects=True) as client:
            r = await client.get(url)
            r.raise_for_status()
            content_type = r.headers.get("Content-Type", "image/jpeg")
            content = r.content
            if not content_type or not content_type.startswith("image/"):
                logger.warning("[PROXY] Non-image content type: %s for URL: %s", content_type, url)
                if content_type and "text/html" in content_type:
                    soup = BeautifulSoup(content, "html.parser")
                    img_tags = soup.find_all("img")
                    if img_tags:
                        for img in img_tags:
                            src = img.get("src")
                            if src and (src.startswith("http") or src.startswith("//")):
                                if src.startswith("//"):
                                    src = "https:" + src
                                logger.info("[PROXY] Found image in HTML: %s", src)
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
    port = int(os.getenv("PORT", 8080))
    host = os.getenv("HOST", "0.0.0.0")
    uvicorn.run("main:app", host=host, port=port, reload=bool(os.getenv("UVICORN_RELOAD", "0") == "1"))
