import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:recipe_keeper/models/recipe.dart';
import 'dart:developer' as developer;

class RecipeExtractionService {
  static const String baseUrl = 'http://localhost:8000';

  Future<Recipe> extractRecipeFromUrl(String url) async {
    try {
      // Send the URL to our backend for extraction
      final extractionResponse = await http.post(
        Uri.parse('$baseUrl/extract_recipe'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Accept-Charset': 'utf-8',
        },
        body: json.encode({'url': url}),
      );

      if (extractionResponse.statusCode != 200) {
        throw Exception('Failed to extract recipe information');
      }

      // Decode the response with UTF-8 encoding
      final extractedData = json.decode(
        utf8.decode(extractionResponse.bodyBytes),
      );

      // Debug log to see the exact data received
      developer.log(
        'Extracted recipe data: $extractedData',
        name: 'RecipeExtraction',
      );

      // Clean up and normalize ingredients if they're still in string format
      List<String> normalizeIngredients(dynamic ingredients) {
        if (ingredients == null) return [];

        if (ingredients is List) {
          return ingredients.map((item) => item.toString()).toList();
        }

        if (ingredients is String) {
          try {
            // Try to parse as JSON if it's a string representation
            final decoded = json.decode(ingredients);
            if (decoded is List) {
              return decoded.map((item) => item.toString()).toList();
            }
          } catch (_) {
            // If parsing fails, split by commas or return as single item
            if (ingredients.contains(',')) {
              return ingredients.split(',').map((s) => s.trim()).toList();
            }
            return [ingredients];
          }
        }

        return [];
      }

      // Parse numeric values with better error handling
      int parseIntSafely(dynamic value) {
        if (value == null) return 0;

        // If it's already an int, return it
        if (value is int) return value;

        // If it's a string, try to parse it
        if (value is String) {
          // Try to extract just the numeric part if there are other characters
          final numericMatch = RegExp(r'(\d+)').firstMatch(value);
          if (numericMatch != null) {
            return int.tryParse(numericMatch.group(1)!) ?? 0;
          }
          return int.tryParse(value) ?? 0;
        }

        // For other types, convert to string first
        return int.tryParse(value.toString()) ?? 0;
      }

      // Get the values with logging
      final prepTime = parseIntSafely(extractedData['prepTime']);
      final cookTime = parseIntSafely(extractedData['cookTime']);
      final servings = parseIntSafely(extractedData['servings']);

      developer.log(
        'Parsed times: prepTime=$prepTime, cookTime=$cookTime, servings=$servings',
        name: 'RecipeExtraction',
      );

      // Convert the extracted data into a Recipe object
      return Recipe(
        title: extractedData['title']?.toString() ?? '',
        description: extractedData['description']?.toString() ?? '',
        ingredients: normalizeIngredients(extractedData['ingredients']),
        instructions: List<String>.from(extractedData['instructions'] ?? []),
        prepTime: prepTime,
        cookTime: cookTime,
        servings: servings,
        imageUrl: '', // We'll need to handle image extraction separately
        sourceUrl: url,
        userId: '', // This will be set when saving the recipe
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        tags: List<String>.from(extractedData['tags'] ?? []),
        isFavorite: false,
      );
    } catch (e) {
      developer.log(
        'Error extracting recipe: $e',
        name: 'RecipeExtraction',
        error: e,
      );
      throw Exception('Failed to extract recipe: ${e.toString()}');
    }
  }
}
