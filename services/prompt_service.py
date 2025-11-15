# services/prompt_service.py
"""Prompt generation for various AI tasks (extraction, OCR, custom, chat)."""

from __future__ import annotations


# ---------------------------------------------------------------------------
# Recipe extraction from text (page, Zyte content, OCR text)
# ---------------------------------------------------------------------------
def create_recipe_extraction_prompt(source_text: str, *, url: str | None = None) -> str:
    """Create a prompt for extracting a recipe from raw text.

    This is used for:
    - page text fetched via httpx/Playwright/Jina
    - Zyte article content
    - OCR text from an image

    The key requirement: **copy ingredients & instructions exactly**.
    """
    url_str = url or ""
    context_line = f"PAGE URL: {url_str}\n" if url_str else ""

    return f"""
You are a STRICT recipe data extraction bot.

Your ONLY job:
- Find the recipe in the given text.
- Copy all ingredients and instructions EXACTLY as written (Hebrew or English).
- Output a SINGLE valid JSON object.

{context_line}
SOURCE TEXT (may contain extra text before/after the recipe):
\"\"\"{source_text[:12000]}\"\"\"

Return EXACTLY ONE JSON object with these keys:

{{
  "title": "Recipe title as written",
  "description": "Short description or summary",
  "ingredients": ["line 1", "line 2", ...],
  "ingredientsGroups": [
    {{
      "category": "EXACT heading text (e.g. 'לציפוי', 'For the cream')",
      "ingredients": ["line 1", "line 2", ...]
    }}
  ],
  "instructions": ["step 1", "step 2", ...],
  "prepTime": 0,
  "cookTime": 0,
  "servings": 1,
  "tags": ["tag1", "tag2"],
  "notes": "Notes if present",
  "imageUrl": "",
  "source": "{url_str}"
}}

CRITICAL RULES (no exceptions):

1. INGREDIENTS
   - Find all ingredient sections (e.g. "מצרכים:", "לציפוי:", "לבצק:", "Ingredients:", "For the filling:").
   - Copy each ingredient line EXACTLY as it appears: same words, same amounts, same units, same typos.
   - If there are sub-headings ("לציפוי", "לקרם", "For the sauce"), create an entry in `ingredientsGroups`
     with `category` = EXACT heading text and `ingredients` = all lines that belong to that section.
   - `ingredients` should contain all ingredients (you may duplicate lines that appear in groups).

2. INSTRUCTIONS
   - Find the preparation / instructions section ("אופן ההכנה", "הוראות הכנה", "Instructions").
   - Each element in `instructions` is a single step string.
   - Copy the text EXACTLY as written. Do NOT translate, paraphrase, fix grammar or change numbers.
   - If the original has numbering or bullets, you may keep them as part of the text.

3. TIMES & SERVINGS
   - `prepTime` and `cookTime` are integers in **minutes**.
   - You may convert expressions like "45 דקות" / "45 minutes" / "1 hour" → minutes.
   - If not mentioned, use 0.
   - `servings` is an integer number of servings; if unknown, use 1.

4. NO INVENTIONS
   - Do NOT add ingredients that are not in the text.
   - Do NOT add steps that are not in the text.
   - Do NOT change amounts, units, or product names.

Output JSON only. No explanation, no markdown, no extra text.
""".strip()


# ---------------------------------------------------------------------------
# Custom recipe from groceries
# ---------------------------------------------------------------------------
def create_custom_recipe_prompt(groceries: str, description: str) -> str:
    """Prompt for generating a recipe from groceries and a short description."""
    return f"""
You are a creative recipe generator.

USER GROCERIES (available ingredients):
\"\"\"{groceries}\"\"\"

USER REQUEST / STYLE DESCRIPTION:
\"\"\"{description}\"\"\"

Create ONE recipe that:
- Uses as many of the given ingredients as reasonable.
- It is allowed to ignore some ingredients if they don't fit the recipe.
- Does NOT use ingredients that are not mentioned, except for basic pantry items
  like salt, pepper, water, oil, sugar (only if really needed).

Return EXACTLY ONE JSON object with the following keys:

{{
  "title": "Recipe name",
  "description": "Short description",
  "ingredients": ["line 1", "line 2", ...],
  "ingredientsGroups": [],
  "instructions": ["step 1", "step 2", ...],
  "prepTime": 15,
  "cookTime": 30,
  "servings": 4,
  "tags": ["tag1", "tag2"],
  "notes": "Notes, including which ingredients were NOT used if relevant",
  "imageUrl": "",
  "source": "SpoonIt AI"
}}

Important:
- Use clear, practical instructions.
- Keep everything in the same language as the user's request (Hebrew or English).
- Respond with JSON ONLY (no explanations, no markdown).
""".strip()


# ---------------------------------------------------------------------------
# Chat-style recipe generation
# ---------------------------------------------------------------------------
def create_chat_system_prompt(language: str) -> str:
    """System prompt for /chat endpoint (always returns JSON recipe)."""
    if language.lower().startswith("he"):
        return (
            "אתה עוזר מתכונים. אתה חייב להחזיר אך ורק אובייקט JSON אחד של מתכון.\n"
            "המשתמש יכתוב מצרכים ורצונות (למשל סוג מטבח, קל/מהיר וכו').\n"
            "הכללים:\n"
            "- השתמש בעיקר במצרכים שהמשתמש נותן. מותר לא להשתמש בכולם.\n"
            "- מותר להשתמש בפריטים בסיסיים (מלח, פלפל, מים, שמן, סוכר) אם צריך.\n"
            "- אל תוסיף מצרכים מיוחדים שלא מופיעים.\n"
            "- התאם את המתכון למה שהמשתמש ביקש.\n"
            "- החזר רק JSON תקין בפורמט הבא:\n"
            "{\n"
            '  "title": "שם המתכון",\n'
            '  "description": "תיאור קצר",\n'
            '  "ingredients": ["מרכיב 1", "מרכיב 2", ...],\n'
            '  "ingredientsGroups": [],\n'
            '  "instructions": ["שלב 1", "שלב 2", ...],\n'
            '  "prepTime": 15,\n'
            '  "cookTime": 30,\n'
            '  "servings": 4,\n'
            '  "tags": ["תג1", "תג2"],\n'
            '  "notes": "הערות נוספות",\n'
            '  "imageUrl": "",\n'
            '  "source": "SpoonIt AI"\n'
            "}\n"
            "שוב: החזר JSON אחד בלבד, ללא טקסט נוסף."
        )
    else:
        return (
            "You are a recipe assistant. You MUST return exactly one JSON recipe object.\n"
            "The user will describe ingredients and what kind of dish they want.\n"
            "Rules:\n"
            "- Use mainly the ingredients the user provides; it's okay to ignore some.\n"
            "- You may use basic pantry items (salt, pepper, oil, water, sugar) if needed.\n"
            "- Do not introduce fancy ingredients that are not mentioned.\n"
            "- Adapt the recipe to the requested style.\n"
            "- Return only valid JSON in this format:\n"
            "{\n"
            '  "title": "Recipe Name",\n'
            '  "description": "Short description",\n'
            '  "ingredients": ["ingredient 1", "ingredient 2", ...],\n'
            '  "ingredientsGroups": [],\n'
            '  "instructions": ["Step 1", "Step 2", ...],\n'
            '  "prepTime": 15,\n'
            '  "cookTime": 30,\n'
            '  "servings": 4,\n'
            '  "tags": ["tag1", "tag2"],\n'
            '  "notes": "Extra notes",\n'
            '  "imageUrl": "",\n'
            '  "source": "SpoonIt AI"\n'
            "}\n"
            "Again: respond with JSON only. No explanations, no markdown."
        )
