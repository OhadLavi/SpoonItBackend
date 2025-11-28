"""Test script to verify chat recipe generation fix."""
import asyncio
import json
import sys
import os

# Add the app directory to the Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'app'))

from app.services.recipe_extractor import RecipeExtractor


async def test_chat_recipe_generation():
    """Test the chat recipe generation with Hebrew input."""
    print("Testing chat recipe generation...")
    print("=" * 60)
    
    # Initialize the recipe extractor
    extractor = RecipeExtractor()
    
    # Build a test prompt similar to what the chat endpoint creates
    prompt_parts = []
    
    # System prompt
    system_prompt = (
        "You are a creative and helpful chef assistant. "
        "Your goal is to help users find recipes, plan meals, and cook with what they have. "
        "If the user provides a list of ingredients, suggest recipes that can be made with them. "
        "If the user asks for a specific recipe, provide it. "
        "Maintain a friendly and encouraging tone. "
        "When the user asks for a recipe, respond with a recipe in JSON format. "
        "Otherwise, provide a helpful text response."
    )
    prompt_parts.append(system_prompt)
    
    # User message
    user_message = "מתכון לעוגיות"
    prompt_parts.append(f"User: {user_message}")
    
    # Recipe generation instruction
    prompt_parts.append(
        f"Based on the user's request, generate a recipe in JSON format matching this exact structure:\n\n"
        f"{{\n"
        f'  "title": "Recipe title",\n'
        f'  "description": "Brief recipe description",\n'
        f'  "language": "he",\n'
        f'  "servings": "Number of servings",\n'
        f'  "prepTimeMinutes": number or null,\n'
        f'  "cookTimeMinutes": number or null,\n'
        f'  "totalTimeMinutes": number or null,\n'
        f'  "ingredientGroups": [\n'
        f'    {{\n'
        f'      "name": "Group name or null",\n'
        f'      "ingredients": [\n'
        f'        {{"raw": "ingredient with amount"}}\n'
        f'      ]\n'
        f'    }}\n'
        f'  ],\n'
        f'  "ingredients": ["flat list of all ingredients with amounts"],\n'
        f'  "instructions": ["detailed step 1", "detailed step 2", ...],\n'
        f'  "notes": ["helpful tip 1", ...] or [],\n'
        f'  "imageUrl": null,\n'
        f'  "images": [],\n'
        f'  "nutrition": {{\n'
        f'    "calories": number or null,\n'
        f'    "protein_g": number or null,\n'
        f'    "fat_g": number or null,\n'
        f'    "carbs_g": number or null,\n'
        f'    "per": "serving" or null\n'
        f'  }}\n'
        f"}}\n\n"
        f"Return ONLY valid JSON, no markdown, no code blocks, no explanations."
    )
    
    full_prompt = "\n\n".join(prompt_parts)
    
    print(f"\nUser message: {user_message}")
    print(f"\nPrompt length: {len(full_prompt)} characters")
    print("\nCalling generate_from_text...")
    
    try:
        recipe = await extractor.generate_from_text(full_prompt)
        print("\n✓ SUCCESS! Recipe generated:")
        print(f"  Title: {recipe.title}")
        print(f"  Language: {recipe.language}")
        print(f"  Ingredients count: {len(recipe.ingredients)}")
        print(f"  Instructions count: {len(recipe.instructions)}")
        
        # Print the full recipe as JSON
        print("\n" + "=" * 60)
        print("Full recipe JSON:")
        print("=" * 60)
        print(json.dumps(recipe.model_dump(), indent=2, ensure_ascii=False))
        
    except Exception as e:
        print(f"\n✗ FAILED with error:")
        print(f"  {type(e).__name__}: {str(e)}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    asyncio.run(test_chat_recipe_generation())
