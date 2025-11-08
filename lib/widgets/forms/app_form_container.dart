import 'package:flutter/material.dart';
import 'package:spoonit/utils/app_theme.dart';

class AppFormContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? borderRadius;
  final List<BoxShadow>? boxShadow;
  final double? borderWidth;
  final bool enabled;

  const AppFormContainer({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.boxShadow,
    this.borderWidth,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Theme-aware colors
    final effectiveBackgroundColor =
        backgroundColor ??
        (isDark ? AppTheme.darkCardColor : AppTheme.backgroundColor);
    final effectiveBorderColor =
        borderColor ??
        (isDark ? AppTheme.darkDividerColor : AppTheme.dividerColor);
    final effectiveBorderRadius = borderRadius ?? 24.0;
    final effectiveBorderWidth = borderWidth ?? 1.0;

    // Default box shadow
    final effectiveBoxShadow =
        boxShadow ??
        [
          BoxShadow(
            color: AppTheme.dividerColor.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 16),
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveBackgroundColor,
        borderRadius: BorderRadius.circular(effectiveBorderRadius),
        border:
            enabled
                ? Border.all(
                  color: effectiveBorderColor,
                  width: effectiveBorderWidth,
                )
                : Border.all(
                  color: effectiveBorderColor.withValues(alpha: 0.5),
                  width: effectiveBorderWidth,
                ),
        boxShadow: enabled ? effectiveBoxShadow : null,
      ),
      child: child,
    );
  }
}

/// A specialized form container for input fields with consistent styling
class AppInputContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final bool hasError;
  final bool isFocused;
  final bool enabled;

  const AppInputContainer({
    super.key,
    required this.child,
    this.margin,
    this.hasError = false,
    this.isFocused = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color borderColor;
    if (hasError) {
      borderColor = AppTheme.errorColor;
    } else if (isFocused) {
      borderColor = AppTheme.primaryColor;
    } else {
      borderColor = isDark ? AppTheme.darkDividerColor : AppTheme.dividerColor;
    }

    return AppFormContainer(
      margin: margin,
      backgroundColor:
          isDark ? AppTheme.darkCardColor : AppTheme.backgroundColor,
      borderColor: borderColor,
      borderWidth: isFocused || hasError ? 2.0 : 1.0,
      enabled: enabled,
      child: child,
    );
  }
}

/// A container for form sections with consistent spacing
class AppFormSection extends StatelessWidget {
  final Widget child;
  final String? title;
  final String? subtitle;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const AppFormSection({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textColor,
                fontFamily: AppTheme.primaryFontFamily,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.secondaryTextColor,
                  fontFamily: AppTheme.primaryFontFamily,
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
          child,
        ],
      ),
    );
  }
}





