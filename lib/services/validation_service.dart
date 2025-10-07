import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:recipe_keeper/utils/app_theme.dart';

/// Service for handling validation logic across the app
class ValidationService {
  /// Check if user is authenticated
  static bool isUserAuthenticated(WidgetRef ref) {
    // Prefer direct FirebaseAuth check to avoid provider timing issues
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) return true;

    // Fallback to provider state
    final authState = ref.read(authProvider);
    return authState.status == AuthStatus.authenticated &&
        authState.user != null;
  }

  /// Validate user authentication and show error if not authenticated
  static bool validateAuthentication(BuildContext context, WidgetRef ref) {
    if (!isUserAuthenticated(ref)) {
      showErrorSnackBar(
        context,
        AppTranslations.getText(ref, 'user_not_authenticated'),
      );
      return false;
    }
    return true;
  }

  /// Validate recipe title
  static bool validateRecipeTitle(
    BuildContext context,
    WidgetRef ref,
    String title,
  ) {
    if (title.trim().isEmpty) {
      showErrorSnackBar(
        context,
        AppTranslations.getText(ref, 'title_required'),
      );
      return false;
    }
    return true;
  }

  /// Validate ingredients list
  static bool validateIngredients(
    BuildContext context,
    WidgetRef ref,
    List<String> ingredients,
  ) {
    if (ingredients.isEmpty ||
        ingredients.every((ingredient) => ingredient.trim().isEmpty)) {
      showErrorSnackBar(
        context,
        AppTranslations.getText(ref, 'at_least_one_ingredient_required'),
      );
      return false;
    }
    return true;
  }

  /// Validate instructions list
  static bool validateInstructions(
    BuildContext context,
    WidgetRef ref,
    List<String> instructions,
  ) {
    if (instructions.isEmpty ||
        instructions.every((instruction) => instruction.trim().isEmpty)) {
      showErrorSnackBar(
        context,
        AppTranslations.getText(ref, 'at_least_one_instruction_required'),
      );
      return false;
    }
    return true;
  }

  /// Validate recipe form data
  static bool validateRecipeForm(
    BuildContext context,
    WidgetRef ref,
    String title,
    List<String> ingredients,
    List<String> instructions, {
    String? categoryId,
  }) {
    // Check authentication first
    if (!validateAuthentication(context, ref)) {
      return false;
    }

    // Validate required fields
    if (!validateRecipeTitle(context, ref, title)) {
      return false;
    }

    if (!validateIngredients(context, ref, ingredients)) {
      return false;
    }

    if (!validateInstructions(context, ref, instructions)) {
      return false;
    }

    // Validate category selection
    if (categoryId == null || categoryId.isEmpty) {
      showErrorSnackBar(
        context,
        AppTranslations.getText(ref, 'category_required'),
      );
      return false;
    }

    return true;
  }

  /// Show error snackbar
  static void showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            color: AppTheme.backgroundColor,
          ),
        ),
        backgroundColor: AppTheme.errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Show success snackbar
  static void showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            color: AppTheme.backgroundColor,
          ),
        ),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

/// Provider for ValidationService
final validationServiceProvider = Provider<ValidationService>(
  (ref) => ValidationService(),
);
