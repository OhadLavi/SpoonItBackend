"""
Recipe Extractor using Google Gemini API
Extracts recipe information from a URL using only the Gemini API.
"""

import os
import json
import google.generativeai as genai
from typing import Dict, Any, Optional
from dotenv import load_dotenv

# Load environment variables from .env file if it exists
load_dotenv()


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
    
    # Initialize the model
    model = genai.GenerativeModel('gemini-pro')
    
    # Create the prompt for recipe extraction
    prompt = f"""Extract the recipe information from this URL: {url}

Please analyze the webpage at this URL and extract the following recipe information in JSON format:

{{
    "title": "Recipe title",
    "description": "Recipe description or summary",
    "ingredients": ["ingredient 1", "ingredient 2", ...],
    "instructions": ["step 1", "step 2", ...],
    "prepTime": 0,
    "cookTime": 0,
    "servings": 1,
    "tags": ["tag1", "tag2", ...],
    "notes": "Any additional notes",
    "source": "{url}",
    "imageUrl": "URL of recipe image if available"
}}

Important guidelines:
- Return ONLY valid JSON, no additional text or markdown formatting
- prepTime and cookTime should be in minutes (as integers)
- ingredients should be a list of strings, each containing the full ingredient with quantities
- instructions should be a list of strings, each representing a step
- If any information is not available, use empty strings for text fields, empty arrays for lists, and 0 for numbers
- Extract the actual recipe content from the webpage, not just metadata
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

