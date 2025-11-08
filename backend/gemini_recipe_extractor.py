"""
Recipe Extractor using Google Gemini API
Extracts recipe information from a URL using only the Gemini API.
"""

import os
import json
import re
import httpx
import google.generativeai as genai
from typing import Dict, Any, Optional
from dotenv import load_dotenv

# Load environment variables from .env file if it exists
load_dotenv()


def fetch_html_content(url: str) -> str:
    """Fetch HTML content from URL and extract visible text (no HTML parsing)."""
    with httpx.Client(timeout=30.0, headers={"User-Agent": "Mozilla/5.0"}) as client:
        r = client.get(url, follow_redirects=True)
        r.raise_for_status()
        html = r.text
        
        # Simple text extraction: remove script and style tags using regex (no BeautifulSoup)
        # Remove script tags and their content
        html = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL | re.IGNORECASE)
        # Remove style tags and their content
        html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.DOTALL | re.IGNORECASE)
        # Remove HTML tags but keep text content
        text = re.sub(r'<[^>]+>', ' ', html)
        # Normalize whitespace
        text = re.sub(r'\s+', ' ', text)
        # Limit size
        if len(text.encode('utf-8')) > 50000:
            text = text[:50000]
        return text.strip()

def extract_recipe_from_url(url: str, api_key: Optional[str] = None) -> Dict[str, Any]:
    """
    Extract recipe information from a URL using Gemini API.
    
    Args:
        url: The URL of the recipe page
        api_key: Google Gemini API key (if not provided, uses GEMINI_API_KEY env var)
    
    Returns:
        Dictionary containing extracted recipe information
    """
    # Get API key from parameter, environment variable, or .env file
    if api_key is None:
        api_key = os.getenv("GEMINI_API_KEY")
    
    if not api_key:
        raise ValueError(
            "Gemini API key is required.\n"
            "Options:\n"
            "  1. Set GEMINI_API_KEY environment variable\n"
            "  2. Create a .env file in the backend directory with: GEMINI_API_KEY=your_key\n"
            "  3. Pass it as a command-line argument: python gemini_recipe_extractor.py <url> <api_key>"
        )
    
    # Configure the Gemini API
    genai.configure(api_key=api_key)
    
    # Fetch HTML content and extract text
    page_text = fetch_html_content(url)
    print(f"Fetched page text, length={len(page_text)}")
    
    # Initialize the model
    model = genai.GenerativeModel('gemini-2.5-flash')
    
    # Create the prompt for recipe extraction with improved guidelines
    prompt = f"""Extract the recipe information from the following webpage content:

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
    
    try:
        # Generate content using Gemini
        response = model.generate_content(prompt)
        
        # Get the text response
        response_text = response.text.strip()
        
        # Clean up the response (remove markdown code blocks if present)
        if response_text.startswith("```"):
            # Remove markdown code fences
            lines = response_text.split("\n")
            if lines[0].startswith("```"):
                lines = lines[1:]
            if lines[-1].strip() == "```":
                lines = lines[:-1]
            response_text = "\n".join(lines)
        
        # Parse JSON response
        recipe_data = json.loads(response_text)
        
        # Process instructions - ensure they are numbered
        instructions = recipe_data.get("instructions", [])
        numbered_instructions = []
        for i, instruction in enumerate(instructions, 1):
            instruction_str = str(instruction).strip()
            # Remove existing numbering if present
            instruction_str = re.sub(r'^\d+[\.\)]\s*', '', instruction_str)
            # Add numbering
            numbered_instructions.append(f"{i}. {instruction_str}")
        recipe_data["instructions"] = numbered_instructions
        
        return recipe_data
        
    except json.JSONDecodeError as e:
        raise ValueError(f"Failed to parse JSON response from Gemini: {e}\nResponse: {response_text}")
    except Exception as e:
        raise RuntimeError(f"Error calling Gemini API: {e}")


def main():
    """Example usage of the recipe extractor."""
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python gemini_recipe_extractor.py <url> [api_key]")
        print("\nExample:")
        print("  python gemini_recipe_extractor.py https://example.com/recipe")
        print("  python gemini_recipe_extractor.py https://example.com/recipe YOUR_API_KEY")
        sys.exit(1)
    
    url = sys.argv[1]
    api_key = sys.argv[2] if len(sys.argv) > 2 else None
    
    try:
        print(f"Extracting recipe from: {url}")
        print("This may take a moment...\n")
        
        recipe = extract_recipe_from_url(url, api_key)
        
        print("Extracted Recipe:")
        print("=" * 50)
        print(json.dumps(recipe, indent=2, ensure_ascii=False))
        
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

