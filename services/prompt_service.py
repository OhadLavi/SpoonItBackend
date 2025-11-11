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


def create_extraction_prompt(url: str, page_text: str) -> str:
    """Create a comprehensive extraction prompt for recipe from webpage."""
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
- e.g. "מצרכים:", "חומרים:", "למילוי:", "לציפוי:", "לבצק:" etc.

STEP 2: COPY INGREDIENTS EXACTLY AS WRITTEN
- If you found section headers → use "ingredientsGroups"
- COPY the section name EXACTLY (including punctuation)
- COPY each ingredient line EXACTLY
- Keep EXACT order and units
- If no section headers → use flat "ingredients" list

STEP 3: COPY INSTRUCTIONS EXACTLY AS WRITTEN
- COPY each step EXACTLY
- Do NOT paraphrase, summarize, or rewrite
- Number the steps "1.", "2.", "3.", ...

Return JSON only. No extra text.
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

