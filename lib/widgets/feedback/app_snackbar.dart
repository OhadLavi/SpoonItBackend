import 'package:flutter/material.dart';
import 'package:spoonit/utils/app_theme.dart';

class AppSnackbar {
  static const Duration _defaultDuration = Duration(seconds: 3);
  static const Duration _longDuration = Duration(seconds: 5);

  /// Show an error snackbar
  static void showError(
    BuildContext context,
    String message, {
    Duration? duration,
    SnackBarAction? action,
    bool showIcon = true,
  }) {
    _showSnackBar(
      context,
      message,
      backgroundColor: AppTheme.errorColor,
      textColor: AppTheme.backgroundColor,
      icon: showIcon ? Icons.error_outline : null,
      duration: duration ?? _defaultDuration,
      action: action,
    );
  }

  /// Show a success snackbar
  static void showSuccess(
    BuildContext context,
    String message, {
    Duration? duration,
    SnackBarAction? action,
    bool showIcon = true,
  }) {
    _showSnackBar(
      context,
      message,
      backgroundColor: AppTheme.successColor,
      textColor: AppTheme.backgroundColor,
      icon: showIcon ? Icons.check_circle_outline : null,
      duration: duration ?? _defaultDuration,
      action: action,
    );
  }

  /// Show a warning snackbar
  static void showWarning(
    BuildContext context,
    String message, {
    Duration? duration,
    SnackBarAction? action,
    bool showIcon = true,
  }) {
    _showSnackBar(
      context,
      message,
      backgroundColor: AppTheme.warningColor,
      textColor: AppTheme.backgroundColor,
      icon: showIcon ? Icons.warning_outlined : null,
      duration: duration ?? _defaultDuration,
      action: action,
    );
  }

  /// Show an info snackbar
  static void showInfo(
    BuildContext context,
    String message, {
    Duration? duration,
    SnackBarAction? action,
    bool showIcon = true,
  }) {
    _showSnackBar(
      context,
      message,
      backgroundColor: AppTheme.primaryColor,
      textColor: AppTheme.backgroundColor,
      icon: showIcon ? Icons.info_outline : null,
      duration: duration ?? _defaultDuration,
      action: action,
    );
  }

  /// Show a neutral snackbar
  static void showNeutral(
    BuildContext context,
    String message, {
    Duration? duration,
    SnackBarAction? action,
    bool showIcon = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    _showSnackBar(
      context,
      message,
      backgroundColor: isDark ? AppTheme.darkCardColor : AppTheme.cardColor,
      textColor: isDark ? AppTheme.darkTextColor : AppTheme.textColor,
      icon: showIcon ? Icons.info_outline : null,
      duration: duration ?? _defaultDuration,
      action: action,
    );
  }

  /// Show a long-duration snackbar (useful for important messages)
  static void showLong(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    Color? textColor,
    IconData? icon,
    SnackBarAction? action,
  }) {
    _showSnackBar(
      context,
      message,
      backgroundColor: backgroundColor ?? AppTheme.primaryColor,
      textColor: textColor ?? AppTheme.backgroundColor,
      icon: icon,
      duration: _longDuration,
      action: action,
    );
  }

  /// Show a custom snackbar with full control
  static void showCustom(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    Color? textColor,
    IconData? icon,
    Duration? duration,
    SnackBarAction? action,
    EdgeInsetsGeometry? margin,
    double? borderRadius,
    bool showIcon = true,
  }) {
    _showSnackBar(
      context,
      message,
      backgroundColor: backgroundColor,
      textColor: textColor,
      icon: showIcon ? icon : null,
      duration: duration ?? _defaultDuration,
      action: action,
      margin: margin,
      borderRadius: borderRadius,
    );
  }

  /// Internal method to show snackbar with consistent styling
  static void _showSnackBar(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    Color? textColor,
    IconData? icon,
    Duration? duration,
    SnackBarAction? action,
    EdgeInsetsGeometry? margin,
    double? borderRadius,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Default colors if not provided
    final effectiveBackgroundColor =
        backgroundColor ??
        (isDark ? AppTheme.darkCardColor : AppTheme.cardColor);
    final effectiveTextColor =
        textColor ?? (isDark ? AppTheme.darkTextColor : AppTheme.textColor);
    final effectiveBorderRadius = borderRadius ?? 8.0;
    final effectiveMargin = margin ?? const EdgeInsets.all(16);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: effectiveTextColor, size: 20),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: effectiveTextColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFamily: AppTheme.primaryFontFamily,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: effectiveBackgroundColor,
        duration: duration ?? _defaultDuration,
        action: action,
        margin: effectiveMargin,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(effectiveBorderRadius),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Clear all snackbars
  static void clear(BuildContext context) {
    ScaffoldMessenger.of(context).clearSnackBars();
  }

  /// Show a snackbar with retry action
  static void showWithRetry(
    BuildContext context,
    String message,
    VoidCallback onRetry, {
    String retryText = 'Retry',
    Color? backgroundColor,
    Color? textColor,
    Duration? duration,
  }) {
    showCustom(
      context,
      message,
      backgroundColor: backgroundColor,
      textColor: textColor,
      duration: duration,
      action: SnackBarAction(
        label: retryText,
        textColor: textColor ?? AppTheme.backgroundColor,
        onPressed: onRetry,
      ),
    );
  }

  /// Show a snackbar with undo action
  static void showWithUndo(
    BuildContext context,
    String message,
    VoidCallback onUndo, {
    String undoText = 'Undo',
    Color? backgroundColor,
    Color? textColor,
    Duration? duration,
  }) {
    showCustom(
      context,
      message,
      backgroundColor: backgroundColor,
      textColor: textColor,
      duration: duration,
      action: SnackBarAction(
        label: undoText,
        textColor: textColor ?? AppTheme.backgroundColor,
        onPressed: onUndo,
      ),
    );
  }
}





