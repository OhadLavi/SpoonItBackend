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

═══════════════════════════════════════════════════════════════
STEP 1: EXTRACT ALL INGREDIENTS (MANDATORY - DO NOT MISS ANY)
═══════════════════════════════════════════════════════════════

🔍 MANDATORY: SEARCH FOR INGREDIENT SECTIONS (Hebrew & English):

Hebrew patterns (MOST COMMON):
- "מצרכים למתכון:" or "מצרכים:" or "חומרים:" → Main ingredients
- "למילוי:" → Filling ingredients
- "לציפוי:" → Topping/coating ingredients  
- "לבצק:" → Dough ingredients
- "לרוטב:" → Sauce ingredients

English patterns:
- "Ingredients:", "For the filling:", "For the dough:", "For topping:"

🚨 EXTRACTION RULES (MANDATORY - NO EXCEPTIONS):

1. EXTRACT EVERY LINE UNDER INGREDIENT SECTIONS:
   - See "מצרכים למתכון:" → Extract ALL lines until next section (למילוי/לציפוי/אופן ההכנה)
   - See "למילוי:" → Extract ALL those lines too
   - See "לציפוי:" → Extract ALL those lines too
   - Keep extracting until you reach instructions section ("אופן ההכנה:" or "הוראות הכנה:")

2. USE "ingredientsGroups" STRUCTURE:
   {{
     "ingredientsGroups": [
       {{"category": "מצרכים למתכון:", "ingredients": ["ingredient 1", "ingredient 2", ...]}},
       {{"category": "למילוי:", "ingredients": ["ingredient 3", "ingredient 4", ...]}},
       {{"category": "לציפוי:", "ingredients": ["ingredient 5", "ingredient 6"]}}
     ],
     "ingredients": []
   }}

3. COPY EXACTLY - ZERO TOLERANCE FOR CHANGES:
   - "1 קילו קמח לחם/חלה/פיצה או קמח לבן רגיל" → EXACT COPY
   - "750 גר׳ בשר טחון" → EXACT COPY (NOT "750 גרם", NOT "0.75 קילו")
   - "בצל גדול חתוך לקוביות קטנות" → EXACT COPY (NOT "1 בצל", NOT "בצל")
   - "2 כפות שמרים יבשים" → EXACT COPY (NOT "2 כפות שמרים")

4. IF NO INGREDIENTS EXTRACTED = COMPLETE FAILURE:
   - Recipes ALWAYS have ingredients
   - Empty "ingredientsGroups" and "ingredients" = YOU FAILED

❌ THESE ARE COMPLETE FAILURES:
- {{"ingredientsGroups": [], "ingredients": []}} when recipe has clear ingredients
- Only extracting "מצרכים למתכון:" and skipping "למילוי:", "לציפוי:"
- Changing ANY word, number, or unit in ingredients
- Missing ingredients from sub-sections

═══════════════════════════════════════════════════════════════
STEP 2: EXTRACT TIME AND SERVINGS (MANDATORY - BE ACCURATE)
═══════════════════════════════════════════════════════════════

🔍 SEARCH FOR TIME INFORMATION:
Look for these patterns (in Hebrew and English):
- Prep time: "זמן הכנה:", "זמן הכנה", "Prep time:", "Preparation:", "Prep:", "הכנה:", etc.
- Cook time: "זמן בישול:", "זמן בישול", "Cook time:", "Cooking time:", "בישול:", etc.
- Total time: "זמן כולל:", "Total time:", "סה\"כ:", etc.
- Look for numbers followed by: "דקות", "דק'", "minutes", "min", "שעות", "hours", "hrs", etc.

🔍 SEARCH FOR SERVINGS INFORMATION:
Look for these patterns:
- "מנות:", "מנות", "Servings:", "Serves:", "מס' מנות:", "מספר מנות:", etc.
- Look for numbers like: "4 מנות", "4 servings", "לכ-4", "לכ- 4", etc.

✅ EXTRACTION RULES:
- prepTime: Extract ONLY preparation time (chopping, mixing, etc.) in MINUTES as integer
  - If you see "15 דקות" or "15 minutes" → prepTime: 15
  - If you see "30 דקות הכנה" → prepTime: 30
  - If you see "1 שעה" or "1 hour" → prepTime: 60
  - If no prep time is mentioned → prepTime: 0
  - DO NOT confuse prep time with cook time or total time

- cookTime: Extract ONLY cooking/baking time in MINUTES as integer
  - If you see "45 דקות" or "45 minutes" → cookTime: 45
  - If you see "1.5 שעות" or "1.5 hours" → cookTime: 90
  - If you see "בישול: 30 דקות" → cookTime: 30
  - If no cook time is mentioned → cookTime: 0
  - DO NOT confuse cook time with prep time or total time

- servings: Extract the number of servings as integer
  - If you see "4 מנות" or "4 servings" → servings: 4
  - If you see "לכ-6" → servings: 6
  - If you see "מס' מנות: 8" → servings: 8
  - If no servings mentioned → servings: 1 (default)
  - Extract the ACTUAL number, not a range (if you see "4-6", use 4 or the first number)

❌ COMMON MISTAKES TO AVOID:
- Setting prepTime = total time (should be separate)
- Setting cookTime = total time (should be separate)
- Confusing hours with minutes (1 hour = 60 minutes)
- Using ranges for servings (use the first number or most common)
- Setting times to 0 when they are clearly mentioned on the page
- Mixing up prep time and cook time

═══════════════════════════════════════════════════════════════
STEP 3: COPY INSTRUCTIONS EXACTLY AS WRITTEN (ZERO TOLERANCE)
═══════════════════════════════════════════════════════════════

🚨 MANDATORY RULES:
- Find the instructions section: "אופן ההכנה:" or "הוראות הכנה:" or "Instructions:"
- COPY each instruction sentence EXACTLY AS WRITTEN - word for word
- Do NOT paraphrase, summarize, rewrite, or simplify
- Do NOT change ANY words, numbers, or descriptions
- Do NOT correct spelling or grammar
- Only add step numbers (1., 2., 3., ...) at the start if not already present
- Extract ALL steps - do not skip any
- If recipe says "מחממים תנור ל 180 מעלות" → Write: "1. מחממים תנור ל 180 מעלות" (NOT "1. Preheat oven to 180 degrees")

❌ INSTRUCTION FAILURES:
- Changing "מכניסים לגומה כף גדושה מאוד של בשר" to "מכניסים כף בשר" (WRONG - removed words)
- Changing "אופים כ 20-25 דקות" to "אופים 25 דקות" (WRONG - changed range)
- Translating Hebrew to English or vice versa (WRONG - keep original language)
- Combining multiple steps into one (WRONG - keep separate)

═══════════════════════════════════════════════════════════════
EXAMPLES OF CORRECT EXTRACTION
═══════════════════════════════════════════════════════════════

✓ Ingredients: Extract ALL of them, even if in different sections
✓ prepTime: If page says "15 דקות הכנה" → prepTime: 15
✓ cookTime: If page says "45 דקות בישול" → cookTime: 45
✓ servings: If page says "4 מנות" → servings: 4

❌ WRONG:
- Missing ingredients from sub-sections
- prepTime: 60 when page says "15 דקות הכנה" (WRONG - you used total time)
- cookTime: 0 when page clearly says "בישול: 30 דקות" (WRONG - you missed it)
- servings: 1 when page says "6 מנות" (WRONG - you didn't extract it)

FORMAT:
{{
  "ingredientsGroups": [
    {{"category": "EXACT header from page", "ingredients": ["EXACT ingredient 1", "EXACT ingredient 2", "EXACT ingredient 3", ...]}},
    {{"category": "EXACT header from page", "ingredients": ["EXACT ingredient 4", ...]}}
  ],
  "ingredients": ["EXACT ingredient 1", "EXACT ingredient 2", ...],
  "instructions": ["1. EXACT instruction text", "2. EXACT instruction text", ...],
  "prepTime": 15,
  "cookTime": 45,
  "servings": 4
}}

⚠️ FINAL CHECKLIST BEFORE RESPONDING:
1. ✅ Did I extract ALL ingredients from ALL sections? (Check the entire page)
2. ✅ Did I extract prepTime correctly? (Only preparation, in minutes)
3. ✅ Did I extract cookTime correctly? (Only cooking/baking, in minutes)
4. ✅ Did I extract servings correctly? (Actual number, not range)
5. ✅ Are all ingredients copied EXACTLY as written?
6. ✅ Are all instructions copied EXACTLY as written?

═══════════════════════════════════════════════════════════════
REAL EXAMPLE: How to Extract from a Hebrew Recipe
═══════════════════════════════════════════════════════════════

If you see this recipe structure:
"לחמניות רכות במילוי בשר טחון/22 לחמניות

מצרכים למתכון:
1 קילו קמח לחם/חלה/פיצה או קמח לבן רגיל
2 כפות שמרים יבשים

למילוי:
750 גר׳ בשר טחון
בצל גדול חתוך לקוביות קטנות

לציפוי:
חלמון ביצה
שומשום

אופן ההכנה:
בקערת המיקסר מערבבים קמח, שמרים יבשים סוכר ומלח..."

YOU MUST EXTRACT:
{{
  "title": "לחמניות רכות במילוי בשר טחון",
  "servings": 22,
  "ingredientsGroups": [
    {{
      "category": "מצרכים למתכון:",
      "ingredients": [
        "1 קילו קמח לחם/חלה/פיצה או קמח לבן רגיל",
        "2 כפות שמרים יבשים"
      ]
    }},
    {{
      "category": "למילוי:",
      "ingredients": [
        "750 גר׳ בשר טחון",
        "בצל גדול חתוך לקוביות קטנות"
      ]
    }},
    {{
      "category": "לציפוי:",
      "ingredients": [
        "חלמון ביצה",
        "שומשום"
      ]
    }}
  ],
  "instructions": [
    "1. בקערת המיקסר מערבבים קמח, שמרים יבשים סוכר ומלח..."
  ]
}}

❌ WRONG EXTRACTIONS (DO NOT DO):
- Changing "22 לחמניות" to "20 rolls" (WRONG - changed number and translated)
- Only extracting "מצרכים למתכון:" and missing "למילוי:", "לציפוי:" (WRONG - incomplete)
- Changing "750 גר׳ בשר טחון" to "750 גרם בשר" (WRONG - changed text)
- Empty ingredientsGroups when recipe clearly has ingredients (WRONG - total failure)

IF YOU MISS ANY INGREDIENTS OR EXTRACT TIMES/SERVINGS INCORRECTLY, YOU HAVE FAILED.
YOUR JOB IS TO COPY ACCURATELY, NOT TO GUESS OR SKIP INFORMATION.
"""


def create_extraction_prompt(url: str, page_text: str) -> str:
    """
    Create extraction prompt with page text (for when HTML is already fetched).
    DEPRECATED: Use create_extraction_prompt_from_url() instead to let Gemini fetch the page.
    This function uses the same enhanced instructions as create_extraction_prompt_from_url().
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

═══════════════════════════════════════════════════════════════
STEP 1: EXTRACT ALL INGREDIENTS (MANDATORY - DO NOT MISS ANY)
═══════════════════════════════════════════════════════════════

🔍 MANDATORY: SEARCH FOR INGREDIENT SECTIONS (Hebrew & English):

Hebrew patterns (MOST COMMON):
- "מצרכים למתכון:" or "מצרכים:" or "חומרים:" → Main ingredients
- "למילוי:" → Filling ingredients
- "לציפוי:" → Topping/coating ingredients  
- "לבצק:" → Dough ingredients
- "לרוטב:" → Sauce ingredients

English patterns:
- "Ingredients:", "For the filling:", "For the dough:", "For topping:"

🚨 EXTRACTION RULES (MANDATORY - NO EXCEPTIONS):

1. EXTRACT EVERY LINE UNDER INGREDIENT SECTIONS:
   - See "מצרכים למתכון:" → Extract ALL lines until next section (למילוי/לציפוי/אופן ההכנה)
   - See "למילוי:" → Extract ALL those lines too
   - See "לציפוי:" → Extract ALL those lines too
   - Keep extracting until you reach instructions section ("אופן ההכנה:" or "הוראות הכנה:")

2. USE "ingredientsGroups" STRUCTURE:
   {{
     "ingredientsGroups": [
       {{"category": "מצרכים למתכון:", "ingredients": ["ingredient 1", "ingredient 2", ...]}},
       {{"category": "למילוי:", "ingredients": ["ingredient 3", "ingredient 4", ...]}},
       {{"category": "לציפוי:", "ingredients": ["ingredient 5", "ingredient 6"]}}
     ],
     "ingredients": []
   }}

3. COPY EXACTLY - ZERO TOLERANCE FOR CHANGES:
   - "1 קילו קמח לחם/חלה/פיצה או קמח לבן רגיל" → EXACT COPY
   - "750 גר׳ בשר טחון" → EXACT COPY (NOT "750 גרם", NOT "0.75 קילו")
   - "בצל גדול חתוך לקוביות קטנות" → EXACT COPY (NOT "1 בצל", NOT "בצל")
   - "2 כפות שמרים יבשים" → EXACT COPY (NOT "2 כפות שמרים")

4. IF NO INGREDIENTS EXTRACTED = COMPLETE FAILURE:
   - Recipes ALWAYS have ingredients
   - Empty "ingredientsGroups" and "ingredients" = YOU FAILED

❌ THESE ARE COMPLETE FAILURES:
- {{"ingredientsGroups": [], "ingredients": []}} when recipe has clear ingredients
- Only extracting "מצרכים למתכון:" and skipping "למילוי:", "לציפוי:"
- Changing ANY word, number, or unit in ingredients
- Missing ingredients from sub-sections

═══════════════════════════════════════════════════════════════
STEP 2: EXTRACT TIME AND SERVINGS (MANDATORY - BE ACCURATE)
═══════════════════════════════════════════════════════════════

🔍 SEARCH FOR TIME INFORMATION:
Look for these patterns (in Hebrew and English):
- Prep time: "זמן הכנה:", "זמן הכנה", "Prep time:", "Preparation:", "Prep:", "הכנה:", etc.
- Cook time: "זמן בישול:", "זמן בישול", "Cook time:", "Cooking time:", "בישול:", etc.
- Total time: "זמן כולל:", "Total time:", "סה\"כ:", etc.
- Look for numbers followed by: "דקות", "דק'", "minutes", "min", "שעות", "hours", "hrs", etc.

🔍 SEARCH FOR SERVINGS INFORMATION:
Look for these patterns:
- "מנות:", "מנות", "Servings:", "Serves:", "מס' מנות:", "מספר מנות:", etc.
- Look for numbers like: "4 מנות", "4 servings", "לכ-4", "לכ- 4", etc.

✅ EXTRACTION RULES:
- prepTime: Extract ONLY preparation time (chopping, mixing, etc.) in MINUTES as integer
  - If you see "15 דקות" or "15 minutes" → prepTime: 15
  - If you see "30 דקות הכנה" → prepTime: 30
  - If you see "1 שעה" or "1 hour" → prepTime: 60
  - If no prep time is mentioned → prepTime: 0
  - DO NOT confuse prep time with cook time or total time

- cookTime: Extract ONLY cooking/baking time in MINUTES as integer
  - If you see "45 דקות" or "45 minutes" → cookTime: 45
  - If you see "1.5 שעות" or "1.5 hours" → cookTime: 90
  - If you see "בישול: 30 דקות" → cookTime: 30
  - If no cook time is mentioned → cookTime: 0
  - DO NOT confuse cook time with prep time or total time

- servings: Extract the number of servings as integer
  - If you see "4 מנות" or "4 servings" → servings: 4
  - If you see "לכ-6" → servings: 6
  - If you see "מס' מנות: 8" → servings: 8
  - If no servings mentioned → servings: 1 (default)
  - Extract the ACTUAL number, not a range (if you see "4-6", use 4 or the first number)

❌ COMMON MISTAKES TO AVOID:
- Setting prepTime = total time (should be separate)
- Setting cookTime = total time (should be separate)
- Confusing hours with minutes (1 hour = 60 minutes)
- Using ranges for servings (use the first number or most common)
- Setting times to 0 when they are clearly mentioned in the content
- Mixing up prep time and cook time

═══════════════════════════════════════════════════════════════
STEP 3: COPY INSTRUCTIONS EXACTLY AS WRITTEN (ZERO TOLERANCE)
═══════════════════════════════════════════════════════════════

🚨 MANDATORY RULES:
- Find the instructions section: "אופן ההכנה:" or "הוראות הכנה:" or "Instructions:"
- COPY each instruction sentence EXACTLY AS WRITTEN - word for word
- Do NOT paraphrase, summarize, rewrite, or simplify
- Do NOT change ANY words, numbers, or descriptions
- Do NOT correct spelling or grammar
- Only add step numbers (1., 2., 3., ...) at the start if not already present
- Extract ALL steps - do not skip any
- If recipe says "מחממים תנור ל 180 מעלות" → Write: "1. מחממים תנור ל 180 מעלות" (NOT "1. Preheat oven to 180 degrees")

❌ INSTRUCTION FAILURES:
- Changing "מכניסים לגומה כף גדושה מאוד של בשר" to "מכניסים כף בשר" (WRONG - removed words)
- Changing "אופים כ 20-25 דקות" to "אופים 25 דקות" (WRONG - changed range)
- Translating Hebrew to English or vice versa (WRONG - keep original language)
- Combining multiple steps into one (WRONG - keep separate)

═══════════════════════════════════════════════════════════════
EXAMPLES OF CORRECT EXTRACTION
═══════════════════════════════════════════════════════════════

✓ Ingredients: Extract ALL of them, even if in different sections
✓ prepTime: If content says "15 דקות הכנה" → prepTime: 15
✓ cookTime: If content says "45 דקות בישול" → cookTime: 45
✓ servings: If content says "4 מנות" → servings: 4

❌ WRONG:
- Missing ingredients from sub-sections
- prepTime: 60 when content says "15 דקות הכנה" (WRONG - you used total time)
- cookTime: 0 when content clearly says "בישול: 30 דקות" (WRONG - you missed it)
- servings: 1 when content says "6 מנות" (WRONG - you didn't extract it)

FORMAT:
{{
  "ingredientsGroups": [
    {{"category": "EXACT header from page", "ingredients": ["EXACT ingredient 1", "EXACT ingredient 2", "EXACT ingredient 3", ...]}},
    {{"category": "EXACT header from page", "ingredients": ["EXACT ingredient 4", ...]}}
  ],
  "ingredients": ["EXACT ingredient 1", "EXACT ingredient 2", ...],
  "instructions": ["1. EXACT instruction text", "2. EXACT instruction text", ...],
  "prepTime": 15,
  "cookTime": 45,
  "servings": 4
}}

⚠️ FINAL CHECKLIST BEFORE RESPONDING:
1. ✅ Did I extract ALL ingredients from ALL sections? (Check the entire content)
2. ✅ Did I extract prepTime correctly? (Only preparation, in minutes)
3. ✅ Did I extract cookTime correctly? (Only cooking/baking, in minutes)
4. ✅ Did I extract servings correctly? (Actual number, not range)
5. ✅ Are all ingredients copied EXACTLY as written?
6. ✅ Are all instructions copied EXACTLY as written?

═══════════════════════════════════════════════════════════════
REAL EXAMPLE: How to Extract from a Hebrew Recipe
═══════════════════════════════════════════════════════════════

If you see this recipe structure:
"לחמניות רכות במילוי בשר טחון/22 לחמניות

מצרכים למתכון:
1 קילו קמח לחם/חלה/פיצה או קמח לבן רגיל
2 כפות שמרים יבשים

למילוי:
750 גר׳ בשר טחון
בצל גדול חתוך לקוביות קטנות

לציפוי:
חלמון ביצה
שומשום

אופן ההכנה:
בקערת המיקסר מערבבים קמח, שמרים יבשים סוכר ומלח..."

YOU MUST EXTRACT:
{{
  "title": "לחמניות רכות במילוי בשר טחון",
  "servings": 22,
  "ingredientsGroups": [
    {{
      "category": "מצרכים למתכון:",
      "ingredients": [
        "1 קילו קמח לחם/חלה/פיצה או קמח לבן רגיל",
        "2 כפות שמרים יבשים"
      ]
    }},
    {{
      "category": "למילוי:",
      "ingredients": [
        "750 גר׳ בשר טחון",
        "בצל גדול חתוך לקוביות קטנות"
      ]
    }},
    {{
      "category": "לציפוי:",
      "ingredients": [
        "חלמון ביצה",
        "שומשום"
      ]
    }}
  ],
  "instructions": [
    "1. בקערת המיקסר מערבבים קמח, שמרים יבשים סוכר ומלח..."
  ]
}}

❌ WRONG EXTRACTIONS (DO NOT DO):
- Changing "22 לחמניות" to "20 rolls" (WRONG - changed number and translated)
- Only extracting "מצרכים למתכון:" and missing "למילוי:", "לציפוי:" (WRONG - incomplete)
- Changing "750 גר׳ בשר טחון" to "750 גרם בשר" (WRONG - changed text)
- Empty ingredientsGroups when recipe clearly has ingredients (WRONG - total failure)

IF YOU MISS ANY INGREDIENTS OR EXTRACT TIMES/SERVINGS INCORRECTLY, YOU HAVE FAILED.
YOUR JOB IS TO COPY ACCURATELY, NOT TO GUESS OR SKIP INFORMATION.
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

