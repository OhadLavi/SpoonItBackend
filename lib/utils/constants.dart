class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String search = '/search';
  static const String myRecipes = '/my-recipes';
  static const String profile = '/profile';
  static const String recipeDetail = '/recipe/:id';
  static const String addRecipe = '/add-recipe';
  static const String editRecipe = '/edit-recipe/:id';
  static const String settings = '/settings';
}

class AppConstants {
  // API Keys and Endpoints
  static const String firebaseWebApiKey = 'YOUR_FIREBASE_WEB_API_KEY';

  // App Settings
  static const int searchDebounceTime = 500; // milliseconds
  static const int maxRecipeImageSize = 2 * 1024 * 1024; // 2MB
  static const int maxRecipeImagesPerRecipe = 5;

  // Recipe Categories
  static const List<String> recipeCategories = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Dessert',
    'Snack',
    'Appetizer',
    'Soup',
    'Salad',
    'Beverage',
    'Baking',
    'Vegetarian',
    'Vegan',
    'Gluten-Free',
    'Dairy-Free',
    'Other',
  ];

  // Measurement Units
  static const List<String> measurementUnits = [
    'teaspoon',
    'tablespoon',
    'cup',
    'fluid ounce',
    'pint',
    'quart',
    'gallon',
    'ounce',
    'pound',
    'gram',
    'kilogram',
    'milliliter',
    'liter',
    'pinch',
    'dash',
    'to taste',
    'piece',
    'slice',
    'whole',
    'clove',
    'bunch',
    'sprig',
    'stalk',
    'head',
    'leaf',
    'package',
    'can',
    'bottle',
    'jar',
    'box',
  ];
}
