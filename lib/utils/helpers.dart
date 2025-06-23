import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/utils/translations.dart';

class Helpers {
  // Format a DateTime to a readable string
  static String formatDateTime(DateTime dateTime) {
    return DateFormat('MMM d, yyyy').format(dateTime);
  }

  // Format minutes to hours and minutes
  static String formatCookingTime(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;

      if (remainingMinutes == 0) {
        return '$hours h';
      } else {
        return '$hours h $remainingMinutes min';
      }
    }
  }

  // Format minutes to hours and minutes with translations
  static String formatCookingTimeWithRef(int minutes, WidgetRef ref) {
    if (minutes < 60) {
      return '$minutes ${AppTranslations.getText(ref, "minutes")}';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;

      if (remainingMinutes == 0) {
        return '$hours ${AppTranslations.getText(ref, "hours")}';
      } else {
        return '$hours ${AppTranslations.getText(ref, "hours")} $remainingMinutes ${AppTranslations.getText(ref, "minutes")}';
      }
    }
  }

  // Launch a URL
  static Future<bool> launchUrl(String url) async {
    final Uri uri = Uri.parse(url);

    if (await url_launcher.canLaunchUrl(uri)) {
      await url_launcher.launchUrl(uri);
      return true;
    } else {
      return false;
    }
  }

  // Show a snackbar
  static void showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.lightBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // Validate email format
  static bool isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  // Validate URL format
  static bool isValidUrl(String url) {
    final urlRegex = RegExp(
      r'^(http|https)://([\w-]+\.)+[\w-]+(/[\w- ./?%&=]*)?$',
      caseSensitive: false,
    );
    return urlRegex.hasMatch(url);
  }

  // Extract domain from URL
  static String getDomainFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return url;
    }
  }

  // Generate a list of tags from recipe title and ingredients
  static List<String> generateTagsFromRecipe(
    String title,
    List<String> ingredients,
  ) {
    final Set<String> tags = {};

    // Common cuisine types
    final cuisines = [
      'italian',
      'mexican',
      'chinese',
      'indian',
      'japanese',
      'thai',
      'french',
      'greek',
      'spanish',
      'mediterranean',
      'american',
    ];

    // Common meal types
    final mealTypes = [
      'breakfast',
      'lunch',
      'dinner',
      'dessert',
      'snack',
      'appetizer',
      'soup',
      'salad',
      'sandwich',
      'pasta',
      'pizza',
      'curry',
    ];

    // Common dietary preferences
    final dietaryPreferences = [
      'vegetarian',
      'vegan',
      'gluten-free',
      'dairy-free',
      'keto',
      'low-carb',
      'paleo',
      'whole30',
      'sugar-free',
    ];

    // Check title for cuisine, meal type, and dietary preferences
    final lowerTitle = title.toLowerCase();

    for (final cuisine in cuisines) {
      if (lowerTitle.contains(cuisine)) {
        tags.add(cuisine);
      }
    }

    for (final mealType in mealTypes) {
      if (lowerTitle.contains(mealType)) {
        tags.add(mealType);
      }
    }

    for (final diet in dietaryPreferences) {
      if (lowerTitle.contains(diet)) {
        tags.add(diet);
      }
    }

    // Check ingredients for dietary preferences
    final allIngredients = ingredients.join(' ').toLowerCase();

    if (!allIngredients.contains('meat') &&
        !allIngredients.contains('chicken') &&
        !allIngredients.contains('beef') &&
        !allIngredients.contains('pork') &&
        !allIngredients.contains('fish') &&
        !allIngredients.contains('seafood')) {
      tags.add('vegetarian');

      if (!allIngredients.contains('milk') &&
          !allIngredients.contains('cheese') &&
          !allIngredients.contains('cream') &&
          !allIngredients.contains('butter') &&
          !allIngredients.contains('egg')) {
        tags.add('vegan');
      }
    }

    if (!allIngredients.contains('flour') &&
        !allIngredients.contains('wheat') &&
        !allIngredients.contains('bread') &&
        !allIngredients.contains('pasta')) {
      tags.add('gluten-free');
    }

    if (!allIngredients.contains('milk') &&
        !allIngredients.contains('cheese') &&
        !allIngredients.contains('cream') &&
        !allIngredients.contains('butter')) {
      tags.add('dairy-free');
    }

    return tags.toList();
  }
}
