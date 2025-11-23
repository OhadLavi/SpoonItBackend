import sys
import os
from pydantic import BaseModel, ValidationError

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

class StrictRecipe(BaseModel):
    title: str

print("--- Testing StrictRecipe (title: str) with None ---")
try:
    StrictRecipe(title=None)
except ValidationError as e:
    print(str(e))

print("\n--- Testing App Recipe (title: Optional[str]) with None ---")
try:
    from app.models.recipe import Recipe
    r = Recipe(title=None, ingredients=[], instructions=[], ingredientGroups=[])
    print("Success! Recipe accepted title=None")
except ValidationError as e:
    print(str(e))
except Exception as e:
    print(f"Import or other error: {e}")

