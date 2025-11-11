"""
Recipe Extractor using Google Gemini API
Extracts recipe information from a URL using only the Gemini API.
"""

# Load environment variables FIRST, before any imports that depend on them
from dotenv import load_dotenv
load_dotenv()

import os
import json
import re
import sys
from typing import Dict, Any, Optional

# Import from refactored modules
from services.prompt_service import create_extraction_prompt_from_url
from services.gemini_service import get_gemini_model


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
    
    # Configure the Gemini API with the provided key
    try:
        import google.generativeai as genai  # type: ignore
        genai.configure(api_key=api_key)
    except ImportError:
        raise ImportError("google-generativeai package is not installed. Install it with: pip install google-generativeai")
    
    # Get the model using the service
    model = get_gemini_model()
    
    # Create the prompt with URL only (Gemini will fetch the page)
    print(f"Extracting recipe from: {url}")
    print("Gemini will fetch and analyze the webpage...")
    prompt = create_extraction_prompt_from_url(url)
    
    try:
        # Generate content using Gemini (it will fetch the URL)
        response = model.generate_content(prompt)
        
        # Get the text response
        response_text = (response.text or "").strip()
        
        if not response_text:
            raise ValueError("Gemini returned empty response")
        
        # Clean up the response (remove markdown code blocks if present)
        if response_text.startswith("```"):
            lines = response_text.split("\n")
            if lines[0].startswith("```"):
                lines = lines[1:]
            if lines and lines[-1].strip() == "```":
                lines = lines[:-1]
            response_text = "\n".join(lines).strip()
        
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
        
        # Ensure source is set
        if not recipe_data.get("source"):
            recipe_data["source"] = url
        
        print("Recipe extracted successfully!")
        return recipe_data
        
    except json.JSONDecodeError as e:
        raise ValueError(f"Failed to parse JSON response from Gemini: {e}\nResponse: {response_text[:500]}")
    except Exception as e:
        raise RuntimeError(f"Error calling Gemini API: {e}")


def main():
    """Example usage of the recipe extractor."""
    if len(sys.argv) < 2:
        print("Usage: python gemini_recipe_extractor.py <url> [api_key]")
        print("\nExample:")
        print("  python gemini_recipe_extractor.py https://example.com/recipe")
        print("  python gemini_recipe_extractor.py https://example.com/recipe YOUR_API_KEY")
        sys.exit(1)
    
    url = sys.argv[1]
    api_key = sys.argv[2] if len(sys.argv) > 2 else None
    
    try:
        recipe = extract_recipe_from_url(url, api_key)
        
        print("\n" + "=" * 60)
        print("EXTRACTED RECIPE:")
        print("=" * 60)
        print(json.dumps(recipe, indent=2, ensure_ascii=False))
        
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

