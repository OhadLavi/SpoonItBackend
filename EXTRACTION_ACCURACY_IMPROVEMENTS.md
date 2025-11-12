# Recipe Extraction Accuracy Improvements

## Problem
Gemini was changing ingredients, instructions, and servings during extraction instead of copying them exactly.

## Solutions Implemented

### 1. **Strict Generation Parameters** ✅
Added deterministic generation settings to minimize randomness:

```python
generation_config = {
    "temperature": 0.0,      # No randomness - completely deterministic
    "top_p": 0.1,            # Very low sampling diversity
    "top_k": 1,              # Only consider the most likely token
    "max_output_tokens": 8192,
    "response_mime_type": "application/json",  # Force JSON output
}
```

**Why this helps:**
- `temperature=0.0` makes the model completely deterministic (no creative variations)
- `top_k=1` forces the model to always pick the single most likely word
- `response_mime_type="application/json"` ensures structured JSON output

### 2. **Aggressive System Instruction** ✅
Added a critical system instruction at the start of every prompt:

```
🚨 CRITICAL SYSTEM INSTRUCTION 🚨
YOU ARE A DATA EXTRACTION ROBOT. YOUR ONLY JOB IS TO COPY TEXT EXACTLY AS WRITTEN.
DO NOT PARAPHRASE. DO NOT TRANSLATE. DO NOT CHANGE ANYTHING.
IF YOU CHANGE EVEN ONE WORD OR NUMBER, THE EXTRACTION HAS FAILED.
```

### 3. **Enhanced Extraction Rules** ✅
- Explicit Hebrew pattern recognition (`מצרכים למתכון:`, `למילוי:`, `לציפוי:`)
- Zero tolerance for changes with specific examples
- Real-world example using the user's actual recipe
- Mandatory checklist before responding

### 4. **Structured Output with ingredientsGroups** ✅
Forces the model to organize ingredients by sections:

```json
{
  "ingredientsGroups": [
    {"category": "מצרכים למתכון:", "ingredients": [...]},
    {"category": "למילוי:", "ingredients": [...]},
    {"category": "לציפוי:", "ingredients": [...]}
  ]
}
```

## Files Modified

1. ✅ `backend/services/prompt_service.py` - Enhanced prompts with aggressive copying instructions
2. ✅ `backend/routes/extraction.py` - Added strict generation config
3. ✅ `backend/gemini_recipe_extractor.py` - Added strict generation config
4. ✅ `backend/extract_recipe_from_url.py` - Added strict generation config

## Optional: Upgrade to More Accurate Model

### Current Model
- `GEMINI_MODEL=gemini-2.5-flash` (fast but less accurate)

### Recommended for Better Accuracy
- `GEMINI_MODEL=gemini-1.5-pro` (slower but significantly more accurate)

To upgrade, set in `.env`:
```bash
GEMINI_MODEL=gemini-1.5-pro
```

**Trade-offs:**
- ✅ **Pro:** Much better at following exact copying instructions
- ✅ **Pro:** Better understanding of complex Hebrew recipes
- ❌ **Con:** ~2-3x slower per request
- ❌ **Con:** Slightly higher API costs

## Testing Recommendations

1. Test with the problematic recipe again
2. Verify all three ingredient sections are extracted (main, filling, topping)
3. Check that ingredient amounts are exact (e.g., "750 גר׳" not "750 גרם")
4. Verify servings match exactly ("22 לחמניות" → servings: 22)
5. Confirm instructions are copied word-for-word

## If Issues Persist

If the model still changes text:

1. **Switch to gemini-1.5-pro** (strongly recommended)
2. **Consider adding post-processing validation** that rejects responses if they don't match certain patterns
3. **Add retry logic** with increasingly strict prompts
4. **Use the deprecated HTML fetching approach** where we fetch HTML ourselves (this worked better for some sites)

## Expected Results

With these changes:
- ✅ Ingredients should be copied exactly as written
- ✅ All ingredient sections should be extracted (main, filling, topping)
- ✅ Servings should match the original number
- ✅ Instructions should be word-for-word copies
- ✅ No translation or paraphrasing

