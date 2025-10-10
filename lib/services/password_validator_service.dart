import 'package:flutter/material.dart';

enum PasswordStrength { weak, medium, strong }

class PasswordValidator {
  // Common passwords list (top 100 most common passwords)
  static const List<String> _commonPasswords = [
    'password',
    '123456',
    '123456789',
    'qwerty',
    'abc123',
    'password123',
    'admin',
    'letmein',
    'welcome',
    'monkey',
    '1234567890',
    'dragon',
    'master',
    'hello',
    'freedom',
    'whatever',
    'qazwsx',
    'trustno1',
    'dragon',
    'batterystaple',
    'pass',
    'freedom',
    'shadow',
    'master',
    'jordan',
    'superman',
    'harley',
    'ranger',
    'hunter',
    'buster',
    'soccer',
    'hockey',
    'killer',
    'george',
    'sexy',
    'andrew',
    'charlie',
    'superman',
    'asshole',
    'fuckyou',
    'dallas',
    'jessica',
    'panties',
    'mike',
    'mustang',
    'shadow',
    'monkey',
    'shadow',
    'master',
    'jordan',
    'superman',
    'harley',
    'ranger',
    'hunter',
    'buster',
    'soccer',
    'hockey',
    'killer',
    'george',
    'sexy',
    'andrew',
    'charlie',
    'superman',
    'asshole',
    'fuckyou',
    'dallas',
    'jessica',
    'panties',
    'mike',
    'mustang',
    'shadow',
    'monkey',
    'shadow',
    'master',
    'jordan',
    'superman',
    'harley',
    'ranger',
    'hunter',
    'buster',
    'soccer',
    'hockey',
    'killer',
    'george',
    'sexy',
    'andrew',
    'charlie',
    'superman',
    'asshole',
    'fuckyou',
    'dallas',
    'jessica',
    'panties',
    'mike',
    'mustang',
  ];

  /// Validates password complexity requirements
  static String? validatePassword(String password) {
    if (password.length < 8) {
      return 'password_too_short';
    }

    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'lowercase_required';
    }

    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'uppercase_required';
    }

    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'number_required';
    }

    if (!RegExp(r'[@$!%*?&]').hasMatch(password)) {
      return 'special_char_required';
    }

    if (_isCommonPassword(password)) {
      return 'common_password';
    }

    return null;
  }

  /// Checks if password is in common passwords list
  static bool _isCommonPassword(String password) {
    return _commonPasswords.contains(password.toLowerCase());
  }

  /// Calculates password strength
  static PasswordStrength calculateStrength(String password) {
    if (password.isEmpty) return PasswordStrength.weak;

    int score = 0;

    // Length bonus
    if (password.length >= 8) score += 1;
    if (password.length >= 12) score += 1;
    if (password.length >= 16) score += 1;

    // Character variety bonus
    if (RegExp(r'[a-z]').hasMatch(password)) score += 1;
    if (RegExp(r'[A-Z]').hasMatch(password)) score += 1;
    if (RegExp(r'[0-9]').hasMatch(password)) score += 1;
    if (RegExp(r'[@$!%*?&]').hasMatch(password)) score += 1;

    // Penalty for common patterns
    if (_isCommonPassword(password)) score -= 2;
    if (RegExp(r'(.)\1{2,}').hasMatch(password)) score -= 1; // Repeated chars
    if (RegExp(r'123|abc|qwe').hasMatch(password.toLowerCase()))
      score -= 1; // Sequential

    if (score <= 2) return PasswordStrength.weak;
    if (score <= 4) return PasswordStrength.medium;
    return PasswordStrength.strong;
  }

  /// Gets color for password strength indicator
  static Color getStrengthColor(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.weak:
        return Colors.red;
      case PasswordStrength.medium:
        return Colors.orange;
      case PasswordStrength.strong:
        return Colors.green;
    }
  }

  /// Gets text for password strength indicator
  static String getStrengthText(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.weak:
        return 'password_weak';
      case PasswordStrength.medium:
        return 'password_medium';
      case PasswordStrength.strong:
        return 'password_strong';
    }
  }

  /// Validates password confirmation
  static String? validatePasswordConfirmation(
    String password,
    String confirmation,
  ) {
    if (confirmation.isEmpty) {
      return 'confirm_password_required';
    }
    if (password != confirmation) {
      return 'passwords_dont_match';
    }
    return null;
  }
}
