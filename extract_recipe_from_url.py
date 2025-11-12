"""
Simple Recipe Extractor from URL using Gemini API
Extracts recipe information from a URL using only the Gemini API.
"""

# Load environment variables FIRST, before any imports that depend on them
from dotenv import load_dotenv
load_dotenv()

import os
import json
import re
import sys
from typing import Dict, Any

from services.prompt_service import create_extraction_prompt_from_url
from services.gemini_service import get_gemini_model


def extract_recipe(url: str) -> Dict[str, Any]:
    """
    Extract recipe from URL using Gemini API.
    
    Args:
        url: The URL of the recipe page
        
    Returns:
        Dictionary containing extracted recipe information
        
    Raises:
        ValueError: If URL is invalid or extraction fails
        ImportError: If required packages are not installed
    """
    if not url or not url.startswith("http"):
        raise ValueError("Invalid URL. Must start with http:// or https://")
    
    # Check if API key is configured
    from config import GEMINI_API_KEY
    if not GEMINI_API_KEY:
        raise ValueError(
            "GEMINI_API_KEY is not set. Please set it in your .env file:\n"
            "GEMINI_API_KEY=your_api_key_here"
        )
    
    # Get Gemini model
    print(f"Extracting recipe from: {url}")
    print("Gemini will fetch and analyze the webpage...")
    model = get_gemini_model()
    
    # Create extraction prompt with URL only (Gemini will fetch the page)
    prompt = create_extraction_prompt_from_url(url)
    
    # Generate recipe using Gemini with strict config for exact copying
    generation_config = {
        "temperature": 0.0,  # No randomness - deterministic output
        "top_p": 0.1,  # Very low sampling diversity
        "top_k": 1,  # Only consider the most likely token
        "max_output_tokens": 8192,
        "response_mime_type": "application/json",  # Force JSON output
    }
    
    response = model.generate_content(prompt, generation_config=generation_config)
    response_text = (response.text or "").strip()
    
    if not response_text:
        raise ValueError("Gemini returned empty response")
    
    # Clean up response (remove markdown code blocks if present)
    if response_text.startswith("```"):
        lines = response_text.split("\n")
        if lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        response_text = "\n".join(lines).strip()
    
    # Parse JSON response
    try:
        recipe_data = json.loads(response_text)
    except json.JSONDecodeError as e:
        raise ValueError(f"Failed to parse JSON response: {e}\nResponse: {response_text[:500]}")
    
    # Ensure instructions are numbered
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


def main():
    """Command-line interface."""
    if len(sys.argv) < 2:
        print("Usage: python extract_recipe_from_url.py <url>")
        print("\nExample:")
        print("  python extract_recipe_from_url.py https://example.com/recipe")
        sys.exit(1)
    
    url = sys.argv[1]
    
    try:
        recipe = extract_recipe(url)
        print("\n" + "=" * 60)
        print("EXTRACTED RECIPE:")
        print("=" * 60)
        print(json.dumps(recipe, indent=2, ensure_ascii=False))
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

