# services/prompt_service.py
"""Prompt generation for various AI tasks."""


def create_recipe_extraction_prompt(section_text: str) -> str:
    """Create a prompt for extracting recipe from text."""
    return (
        "את/ה מומחה/ית לחילוץ מתכונים. החזר/י אך ורק אובייקט JSON תקין יחיד (ללא טקסט נוסף), "
        "בדיוק עם המפתחות: title, description, ingredients, instructions, prepTime, cookTime, servings, tags, imageUrl, source.\n"
        "כללים: 1) החזר JSON בלבד; 2) numbers כמספרים (לא מחרוזות); 3) ללא פסקים מיותרים; 4) ללא המצאות;\n"
        "- ingredients ו-instructions הן מערכים של מחרוזות נקיות (ללא מספור/תבליטים).\n"
        "- prepTime/cookTime בדקות שלמות (int).\n"
        "- servings מספר שלם.\n\n"
        "טקסט המתכון (האזור הרלוונטי):\n"
        f"{section_text}\n"
        "סיום."
    )


def create_chat_system_prompt(language: str) -> str:
    """Create system prompt for recipe chat assistant."""
    if language.lower().startswith("he"):
        return (
            "אתה עוזר AI מומחה במתכונים. אתה יכול רק לעזור ביצירת מתכונים מבוססי מצרכים וסגנון בישול.\n"
            "אם המשתמש שואל משהו שאינו קשור למתכונים, בקש ממנו בנימוס:\n"
            "1. לספק רשימת מצרכים זמינים\n"
            "2. לתאר איזה סוג מתכון הוא רוצה (איטלקי, אסייתי, טבעוני, מהיר, וכו')\n\n"
            "כשהמשתמש מספק מצרכים וסגנון, צור JSON של מתכון בפורמט הבא:\n"
            "{\n"
            '  "title": "שם המתכון",\n'
            '  "description": "תיאור קצר",\n'
            '  "ingredients": ["מרכיב 1", "מרכיב 2", ...],\n'
            '  "instructions": ["1. שלב 1", "2. שלב 2", ...],\n'
            '  "prepTime": 15,\n'
            '  "cookTime": 30,\n'
            '  "servings": 4,\n'
            '  "tags": ["תג1", "תג2"],\n'
            '  "notes": "הערות נוספות",\n'
            '  "imageUrl": "",\n'
            '  "source": "SpoonIt AI"\n'
            "}\n\n"
            "הערות חשובות:\n"
            "- השתמש רק במצרכים שהמשתמש מציין\n"
            "- אם חסרים מצרכים חיוניים, הזכר זאת בהערות\n"
            "- התאם את המתכון לסגנון המבוקש\n"
            "- מספר את ההוראות בצורה ברורה"
        )
    else:
        return (
            "You are an AI recipe assistant. You can ONLY help with creating recipes based on available ingredients and cooking style.\n"
            "If the user asks anything not related to recipes, politely ask them to:\n"
            "1. Provide a list of available ingredients\n"
            "2. Describe what type of recipe they want (Italian, Asian, vegan, quick, etc.)\n\n"
            "When the user provides ingredients and style, create a recipe JSON in this format:\n"
            "{\n"
            '  "title": "Recipe Name",\n'
            '  "description": "Brief description",\n'
            '  "ingredients": ["ingredient 1", "ingredient 2", ...],\n'
            '  "instructions": ["1. Step 1", "2. Step 2", ...],\n'
            '  "prepTime": 15,\n'
            '  "cookTime": 30,\n'
            '  "servings": 4,\n'
            '  "tags": ["tag1", "tag2"],\n'
            '  "notes": "Additional notes",\n'
            '  "imageUrl": "",\n'
            '  "source": "SpoonIt AI"\n'
            "}\n\n"
            "Important notes:\n"
            "- Use only ingredients the user mentions\n"
            "- If essential ingredients are missing, mention it in notes\n"
            "- Adapt the recipe to the requested style\n"
            "- Number the instructions clearly"
        )


def create_extraction_prompt_from_url(url: str) -> str:
    """Create a prompt for extracting recipe directly from a URL (Gemini will fetch the page)."""
    return f"""Visit this URL and extract the recipe information from the webpage:

URL: {url}

Extract the recipe information in JSON format:

{{
    "title": "Recipe title",
    "description": "Recipe description or summary",
    "ingredients": ["ingredient 1", "ingredient 2", ...],
    "ingredientsGroups": [
        {{"category": "Category name as written on page", "ingredients": ["ingredient 1", "ingredient 2"]}},
        {{"category": "Another category name", "ingredients": ["ingredient 3", "ingredient 4"]}}
    ],
    "instructions": ["step 1", "step 2", ...],
    "prepTime": 0,
    "cookTime": 0,
    "servings": 1,
    "tags": ["tag1", "tag2", ...],
    "notes": "Any additional notes",
    "source": "{url}",
    "imageUrl": "URL of recipe image if available"
}}

⚠️ CRITICAL - YOUR TASK IS TO COPY, NOT TO CREATE OR MODIFY ⚠️

YOU ARE A COPY MACHINE, NOT A WRITER. DO NOT CHANGE ANYTHING.

STEP 1: FIND INGREDIENTS SECTIONS
Look in the content for headers like:
- "מצרכים למתכון:" or "מצרכים:" or "חומרים:"
- "למילוי:" or "מילוי:"
- "לציפוי:" or "ציפוי:"
- "לבצק:" or "בצק:"
- Any other section headers before ingredient lists

STEP 2: COPY INGREDIENTS EXACTLY AS WRITTEN
- If you found section headers → use "ingredientsGroups"
- COPY the section name EXACTLY (including colons if present)
- COPY each ingredient line EXACTLY as written
- Keep EXACT amounts: "1 קילו" stays "1 קילו" (NOT "1 קג", NOT "1000 גרם")
- Keep EXACT units: "750 גר׳" stays "750 גר׳" (NOT "0.75 קילו")
- Keep EXACT order as on page
- Do NOT add words, remove words, or change words
- If no section headers exist → use flat "ingredients" list

STEP 3: COPY INSTRUCTIONS EXACTLY AS WRITTEN
- COPY each instruction sentence EXACTLY
- Do NOT paraphrase, summarize, or rewrite
- Do NOT change any words
- Just add numbers (1., 2., 3., ...) at the start of each step

EXAMPLES OF WRONG (DO NOT DO THIS):
❌ Original: "1 קילו קמח" → You write: "1 קג קמח" (WRONG - changed unit)
❌ Original: "750 גר׳ בשר טחון" → You write: "400 גרם בשר בקר טחון" (WRONG - changed amount and added words)
❌ Original: "בצל גדול" → You write: "1 בצל בינוני, קצוץ דק" (WRONG - changed everything)

EXAMPLES OF CORRECT (DO THIS):
✓ Original: "1 קילו קמח" → You write: "1 קילו קמח" (CORRECT - exact copy)
✓ Original: "750 גר׳ בשר טחון" → You write: "750 גר׳ בשר טחון" (CORRECT - exact copy)
✓ Original: "בצל גדול" → You write: "בצל גדול" (CORRECT - exact copy)

FORMAT:
{{
  "ingredientsGroups": [
    {{"category": "EXACT header from page", "ingredients": ["EXACT ingredient 1", "EXACT ingredient 2"]}},
    {{"category": "EXACT header from page", "ingredients": ["EXACT ingredient 3"]}}
  ],
  "ingredients": [],
  "instructions": ["1. EXACT instruction text", "2. EXACT instruction text"]
}}

IF YOU CHANGE ANY INGREDIENT AMOUNT, NAME, OR INSTRUCTION WORDING, YOU HAVE FAILED.
YOUR JOB IS TO COPY, NOT TO WRITE.
"""


def create_extraction_prompt(url: str, page_text: str) -> str:
    """
    Create extraction prompt with page text (for when HTML is already fetched).
    DEPRECATED: Use create_extraction_prompt_from_url() instead to let Gemini fetch the page.
    """
    return f"""Extract the recipe information from the following webpage content:

URL: {url}

Webpage content:
{page_text}

Extract the recipe information in JSON format:

{{
    "title": "Recipe title",
    "description": "Recipe description or summary",
    "ingredients": ["ingredient 1", "ingredient 2", ...],
    "ingredientsGroups": [
        {{"category": "Category name as written on page", "ingredients": ["ingredient 1", "ingredient 2"]}},
        {{"category": "Another category name", "ingredients": ["ingredient 3", "ingredient 4"]}}
    ],
    "instructions": ["step 1", "step 2", ...],
    "prepTime": 0,
    "cookTime": 0,
    "servings": 1,
    "tags": ["tag1", "tag2", ...],
    "notes": "Any additional notes",
    "source": "{url}",
    "imageUrl": "URL of recipe image if available"
}}

⚠️ CRITICAL - YOUR TASK IS TO COPY, NOT TO CREATE OR MODIFY ⚠️

YOU ARE A COPY MACHINE, NOT A WRITER. DO NOT CHANGE ANYTHING.

STEP 1: FIND INGREDIENTS SECTIONS
Look in the content for headers like:
- "מצרכים למתכון:" or "מצרכים:" or "חומרים:"
- "למילוי:" or "מילוי:"
- "לציפוי:" or "ציפוי:"
- "לבצק:" or "בצק:"
- Any other section headers before ingredient lists

STEP 2: COPY INGREDIENTS EXACTLY AS WRITTEN
- If you found section headers → use "ingredientsGroups"
- COPY the section name EXACTLY (including colons if present)
- COPY each ingredient line EXACTLY as written
- Keep EXACT amounts: "1 קילו" stays "1 קילו" (NOT "1 קג", NOT "1000 גרם")
- Keep EXACT units: "750 גר׳" stays "750 גר׳" (NOT "0.75 קילו")
- Keep EXACT order as on page
- Do NOT add words, remove words, or change words
- If no section headers exist → use flat "ingredients" list

STEP 3: COPY INSTRUCTIONS EXACTLY AS WRITTEN
- COPY each instruction sentence EXACTLY
- Do NOT paraphrase, summarize, or rewrite
- Do NOT change any words
- Just add numbers (1., 2., 3., ...) at the start of each step

EXAMPLES OF WRONG (DO NOT DO THIS):
❌ Original: "1 קילו קמח" → You write: "1 קג קמח" (WRONG - changed unit)
❌ Original: "750 גר׳ בשר טחון" → You write: "400 גרם בשר בקר טחון" (WRONG - changed amount and added words)
❌ Original: "בצל גדול" → You write: "1 בצל בינוני, קצוץ דק" (WRONG - changed everything)

EXAMPLES OF CORRECT (DO THIS):
✓ Original: "1 קילו קמח" → You write: "1 קילו קמח" (CORRECT - exact copy)
✓ Original: "750 גר׳ בשר טחון" → You write: "750 גר׳ בשר טחון" (CORRECT - exact copy)
✓ Original: "בצל גדול" → You write: "בצל גדול" (CORRECT - exact copy)

FORMAT:
{{
  "ingredientsGroups": [
    {{"category": "EXACT header from page", "ingredients": ["EXACT ingredient 1", "EXACT ingredient 2"]}},
    {{"category": "EXACT header from page", "ingredients": ["EXACT ingredient 3"]}}
  ],
  "ingredients": [],
  "instructions": ["1. EXACT instruction text", "2. EXACT instruction text"]
}}

IF YOU CHANGE ANY INGREDIENT AMOUNT, NAME, OR INSTRUCTION WORDING, YOU HAVE FAILED.
YOUR JOB IS TO COPY, NOT TO WRITE.
"""


def create_custom_recipe_prompt(groceries: str, description: str) -> str:
    """Create a prompt for generating a custom recipe from groceries and description."""
    return (
        "את/ה יוצר/ת מתכונים. בנה/י JSON יחיד ותקין בלבד.\n"
        f"מצרכים זמינים: {groceries}\n"
        f"תיאור בקשה: {description}\n\n"
        "החזר/י אך ורק אובייקט עם המפתחות: "
        "{title, description, ingredients, instructions, prepTime, cookTime, servings, tags, imageUrl, source}.\n"
        "חוקים: JSON תקין בלבד; ללא פסיקים מיותרים; מספרים לא במרכאות."
    )

