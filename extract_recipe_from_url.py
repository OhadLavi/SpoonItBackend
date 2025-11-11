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
import asyncio
from typing import Dict, Any

from services.prompt_service import create_extraction_prompt
from services.gemini_service import get_gemini_model
from services.fetcher_service import fetch_html_content


async def extract_recipe_async(url: str) -> Dict[str, Any]:
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
    
    # Fetch HTML content from URL
    print(f"Fetching content from: {url}")
    page_text = await fetch_html_content(url)
    print(f"Fetched {len(page_text)} characters")
    
    # Get Gemini model
    model = get_gemini_model()
    
    # Create extraction prompt
    prompt = create_extraction_prompt(url, page_text)
    
    # Generate recipe using Gemini
    print("Extracting recipe with Gemini...")
    response = model.generate_content(prompt)
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


def extract_recipe(url: str) -> Dict[str, Any]:
    """
    Synchronous wrapper for extract_recipe_async.
    
    Args:
        url: The URL of the recipe page
        
    Returns:
        Dictionary containing extracted recipe information
    """
    return asyncio.run(extract_recipe_async(url))


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

