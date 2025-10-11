import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoonit/utils/translations.dart';
import 'package:spoonit/utils/app_theme.dart';

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
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.infoColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // Simplify authentication error messages for better UX
  static String simplifyAuthError(String error) {
    // Common Firebase Auth error patterns
    if (error.contains('user-not-found')) {
      return 'המשתמש לא נמצא. בדוק את כתובת האימייל';
    } else if (error.contains('wrong-password')) {
      return 'הסיסמה שגויה. נסה שוב';
    } else if (error.contains('invalid-email')) {
      return 'כתובת אימייל לא תקינה';
    } else if (error.contains('user-disabled')) {
      return 'החשבון הושבת. פנה לתמיכה';
    } else if (error.contains('too-many-requests')) {
      return 'יותר מדי ניסיונות. המתן רגע ונסה שוב';
    } else if (error.contains('email-already-in-use')) {
      return 'כתובת האימייל כבר בשימוש';
    } else if (error.contains('weak-password')) {
      return 'הסיסמה חלשה מדי. בחר סיסמה חזקה יותר';
    } else if (error.contains('network-request-failed')) {
      return 'בעיית חיבור לאינטרנט. בדוק את החיבור';
    } else if (error.contains('invalid-credential')) {
      return 'פרטי ההתחברות שגויים';
    } else if (error.contains('account-exists-with-different-credential')) {
      return 'החשבון קיים עם שיטת התחברות אחרת';
    } else if (error.contains('operation-not-allowed')) {
      return 'הפעולה לא מורשית';
    } else if (error.contains('requires-recent-login')) {
      return 'נדרש להתחבר מחדש לביטחון';
    } else {
      // For any other errors, show a generic message
      return 'אירעה שגיאה. נסה שוב מאוחר יותר';
    }
  }

  // Validate email format with enhanced regex
  static bool isValidEmail(String email) {
    if (email.isEmpty) return false;

    // More strict email validation
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$',
    );

    // Additional checks
    if (email.length > 254) return false; // RFC 5321 limit
    if (email.startsWith('.') || email.endsWith('.')) return false;
    if (email.contains('..')) return false; // No consecutive dots
    if (email.split('@').length != 2) return false; // Exactly one @

    return emailRegex.hasMatch(email);
  }

  // Validate URL format with enhanced validation
  static bool isValidUrl(String url) {
    if (url.isEmpty) return false;

    try {
      final uri = Uri.parse(url);

      // Check scheme
      if (!['http', 'https'].contains(uri.scheme)) return false;

      // Check host
      if (uri.host.isEmpty) return false;

      // Check for valid domain format
      if (!RegExp(
        r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$',
      ).hasMatch(uri.host)) {
        return false;
      }

      // Check length limits
      if (url.length > 2048) return false; // RFC 7230 limit

      return true;
    } catch (e) {
      return false;
    }
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
