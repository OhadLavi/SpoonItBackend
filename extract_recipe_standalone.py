"""
Standalone Recipe Extractor from URL using Gemini API
This version correctly fetches the page content *before* sending it to Gemini.
"""

# Load environment variables FIRST
from dotenv import load_dotenv
load_dotenv()

import os
import json
import re
import sys
import requests  # For downloading the webpage
from bs4 import BeautifulSoup  # For cleaning the HTML
from typing import Dict, Any, Optional

try:
    import google.generativeai as genai
except ImportError:
    print("Error: 'google.generativeai' library not found.")
    print("Please install it using: pip install google.generativeai")
    genai = None

def clean_json_response(text: str) -> str:
    """
    Cleans the raw text response from Gemini to extract the JSON blob.
    """
    match = re.search(r'```json\n(.*?)\n```', text, re.DOTALL | re.IGNORECASE)
    if match:
        return match.group(1).strip()
    
    start = text.find('{')
    end = text.rfind('}')
    
    if start != -1 and end != -1 and end > start:
        return text[start:end+1].strip()
        
    return text.strip()

def get_page_content(url: str) -> str:
    """
    Fetches the URL and returns its clean, readable text content.
    """
    try:
        response = requests.get(url, headers={'User-Agent': 'Mozilla/5.0'})
        response.raise_for_status()  # Raise an error for bad responses
        
        # Use BeautifulSoup to parse the HTML and get text
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # Find the main recipe article, or just get all text
        # This selector is specific to this site's recipe block
        recipe_body = soup.find('div', class_='recipie-content')
        
        if recipe_body:
            return recipe_body.get_text(separator=' ', strip=True)
        else:
            # Fallback if the specific class isn't found
            return soup.body.get_text(separator=' ', strip=True)

    except requests.RequestException as e:
        print(f"Error fetching URL {url}: {e}")
        return None

def extract_recipe_with_gemini(page_content: str, json_format: str) -> str:
    """
    Calls the Gemini API to extract a recipe from text content.
    """
    if genai is None:
        raise ImportError("google.generativeai library is not available.")

    model = genai.GenerativeModel('gemini-2.5-pro')
    
    # The prompt is now different. We're giving it the *content*, not the URL.
    prompt = f"""
Given the following webpage text, extract the recipe information into the specified JSON format.

JSON FORMAT TO USE:
{json_format}

WEBPAGE TEXT:
{page_content[:10000]}
""" # Limit to first 10k chars to be safe, though Pro can handle more

    print("--- Sending Prompt to Gemini (with page content) ---")
    
    response = model.generate_content(prompt)
    return response.text

def main():
    if genai is None:
        sys.exit(1)

    api_key = os.environ.get("GEMINI_API_KEY") # Changed from GEMINI_API_KEY to match your first script
    if not api_key:
        print("Error: GEMINI_API_KEY not found in environment variables.")
        sys.exit(1)
        
    genai.configure(api_key=api_key)

    url_to_extract = "https://kerenagam.co.il/%d7%a8%d7%95%d7%9c%d7%93%d7%aa-%d7%98%d7%99%d7%a8%d7%9e%d7%99%d7%a1%d7%95-%d7%99%d7%a4%d7%99%d7%a4%d7%99%d7%99%d7%94/#recipies"
    
    # *** THIS IS THE CORRECTED JSON TEMPLATE ***
    json_format_template = """{
  "title": "Recipe Title",
  "servings": 1,
  "ingredientsGroups": [
    {
      "category": "Category Name",
      "ingredients": [
        "ingredient 1",
        "ingredient 2"
      ]
    }
  ],
  "instructions": [
    "Step 1...",
    "Step 2..."
  ]
}"""

    # 1. Fetch the actual page content
    print(f"Fetching content from {url_to_extract}...")
    content = get_page_content(url_to_extract)
    
    if not content:
        print("Could not fetch page content. Exiting.")
        sys.exit(1)
        
    print("...Successfully fetched page content.")

    # 2. Call the API with the content
    try:
        raw_response = extract_recipe_with_gemini(content, json_format_template)
        
        print("\n--- Raw Response from Gemini ---")
        print(raw_response)
        
        # 3. Clean and parse the response
        cleaned_json_str = clean_json_response(raw_response)
        
        print("\n--- Cleaned JSON String ---")
        print(cleaned_json_str)

        try:
            parsed_json = json.loads(cleaned_json_str)
            print("\n--- SUCCESSFULLY PARSED JSON (Pretty Printed) ---")
            print(json.dumps(parsed_json, indent=2, ensure_ascii=False))
            
        except json.JSONDecodeError as e:
            print(f"\n--- ERROR: Failed to decode JSON ---")
            print(f"Error: {e}")

    except Exception as e:
        print(f"\nAn error occurred during the API call: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()