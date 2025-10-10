import 'dart:math' as math;

class InputSanitizer {
  // Maximum lengths for different input types
  static const int maxGeneralTextLength = 1000;
  static const int maxNameLength = 500;
  static const int maxEmailLength = 254;
  static const int maxUrlLength = 2048;
  static const int maxRecipeTitleLength = 200;
  static const int maxIngredientLength = 500;
  static const int maxInstructionLength = 2000;

  /// Sanitizes general text input
  static String sanitizeText(String input) {
    if (input.isEmpty) return input;

    return input
        .trim()
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll(
          RegExp(
            r'[<>"\'
            ']',
          ),
          '',
        ) // Remove dangerous characters
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .substring(0, math.min(input.length, maxGeneralTextLength));
  }

  /// Sanitizes display name input
  static String sanitizeDisplayName(String input) {
    if (input.isEmpty) return input;

    return input
        .trim()
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll(
          RegExp(
            r'[<>"\'
            ']',
          ),
          '',
        ) // Remove dangerous characters
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .substring(0, math.min(input.length, maxNameLength));
  }

  /// Sanitizes email address
  static String sanitizeEmail(String email) {
    if (email.isEmpty) return email;

    return email
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '') // Remove all whitespace
        .substring(0, math.min(email.length, maxEmailLength));
  }

  /// Sanitizes and validates URL
  static String sanitizeUrl(String url) {
    if (url.isEmpty) return url;

    final trimmed = url.trim();

    try {
      // Add protocol if missing
      String urlWithProtocol = trimmed;
      if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
        urlWithProtocol = 'https://$trimmed';
      }

      final uri = Uri.parse(urlWithProtocol);

      // Validate scheme
      if (!['http', 'https'].contains(uri.scheme)) {
        throw FormatException('Invalid URL scheme');
      }

      // Validate host
      if (uri.host.isEmpty) {
        throw FormatException('Invalid host');
      }

      return uri.toString().substring(
        0,
        math.min(uri.toString().length, maxUrlLength),
      );
    } catch (e) {
      throw FormatException('Invalid URL format: $e');
    }
  }

  /// Sanitizes recipe title
  static String sanitizeRecipeTitle(String title) {
    if (title.isEmpty) return title;

    return title
        .trim()
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll(
          RegExp(
            r'[<>"\'
            ']',
          ),
          '',
        ) // Remove dangerous characters
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .substring(0, math.min(title.length, maxRecipeTitleLength));
  }

  /// Sanitizes ingredient text
  static String sanitizeIngredient(String ingredient) {
    if (ingredient.isEmpty) return ingredient;

    return ingredient
        .trim()
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll(
          RegExp(
            r'[<>"\'
            ']',
          ),
          '',
        ) // Remove dangerous characters
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .substring(0, math.min(ingredient.length, maxIngredientLength));
  }

  /// Sanitizes instruction text
  static String sanitizeInstruction(String instruction) {
    if (instruction.isEmpty) return instruction;

    return instruction
        .trim()
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll(
          RegExp(
            r'[<>"\'
            ']',
          ),
          '',
        ) // Remove dangerous characters
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .substring(0, math.min(instruction.length, maxInstructionLength));
  }

  /// Sanitizes list of ingredients
  static List<String> sanitizeIngredients(List<String> ingredients) {
    return ingredients
        .map((ingredient) => sanitizeIngredient(ingredient))
        .where((ingredient) => ingredient.isNotEmpty)
        .toList();
  }

  /// Sanitizes list of instructions
  static List<String> sanitizeInstructions(List<String> instructions) {
    return instructions
        .map((instruction) => sanitizeInstruction(instruction))
        .where((instruction) => instruction.isNotEmpty)
        .toList();
  }

  /// Sanitizes tags list
  static List<String> sanitizeTags(List<String> tags) {
    return tags
        .map((tag) => sanitizeText(tag))
        .where((tag) => tag.isNotEmpty)
        .toSet() // Remove duplicates
        .toList();
  }

  /// Validates that text is not empty after sanitization
  static bool isValidText(String text) {
    return sanitizeText(text).isNotEmpty;
  }

  /// Validates that email is properly formatted after sanitization
  static bool isValidEmail(String email) {
    final sanitized = sanitizeEmail(email);
    if (sanitized.isEmpty) return false;

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(sanitized);
  }

  /// Validates that URL is properly formatted after sanitization
  static bool isValidUrl(String url) {
    try {
      sanitizeUrl(url);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Sanitizes user profile data
  static Map<String, dynamic> sanitizeUserProfile(
    Map<String, dynamic> profile,
  ) {
    final sanitized = <String, dynamic>{};

    if (profile.containsKey('displayName')) {
      sanitized['displayName'] = sanitizeDisplayName(
        profile['displayName']?.toString() ?? '',
      );
    }

    if (profile.containsKey('email')) {
      sanitized['email'] = sanitizeEmail(profile['email']?.toString() ?? '');
    }

    if (profile.containsKey('photoURL')) {
      final photoUrl = profile['photoURL']?.toString() ?? '';
      if (photoUrl.isNotEmpty) {
        try {
          sanitized['photoURL'] = sanitizeUrl(photoUrl);
        } catch (e) {
          // If URL is invalid, remove it
          sanitized['photoURL'] = '';
        }
      }
    }

    return sanitized;
  }

  /// Sanitizes recipe data
  static Map<String, dynamic> sanitizeRecipeData(Map<String, dynamic> recipe) {
    final sanitized = <String, dynamic>{};

    if (recipe.containsKey('title')) {
      sanitized['title'] = sanitizeRecipeTitle(
        recipe['title']?.toString() ?? '',
      );
    }

    if (recipe.containsKey('description')) {
      sanitized['description'] = sanitizeText(
        recipe['description']?.toString() ?? '',
      );
    }

    if (recipe.containsKey('ingredients')) {
      final ingredients = recipe['ingredients'] as List<dynamic>? ?? [];
      sanitized['ingredients'] = sanitizeIngredients(
        ingredients.map((e) => e.toString()).toList(),
      );
    }

    if (recipe.containsKey('instructions')) {
      final instructions = recipe['instructions'] as List<dynamic>? ?? [];
      sanitized['instructions'] = sanitizeInstructions(
        instructions.map((e) => e.toString()).toList(),
      );
    }

    if (recipe.containsKey('tags')) {
      final tags = recipe['tags'] as List<dynamic>? ?? [];
      sanitized['tags'] = sanitizeTags(tags.map((e) => e.toString()).toList());
    }

    if (recipe.containsKey('notes')) {
      sanitized['notes'] = sanitizeText(recipe['notes']?.toString() ?? '');
    }

    if (recipe.containsKey('source')) {
      final source = recipe['source']?.toString() ?? '';
      if (source.isNotEmpty) {
        try {
          sanitized['source'] = sanitizeUrl(source);
        } catch (e) {
          sanitized['source'] = sanitizeText(source);
        }
      }
    }

    return sanitized;
  }
}
