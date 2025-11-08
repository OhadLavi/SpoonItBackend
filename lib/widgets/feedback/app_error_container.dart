import 'package:flutter/material.dart';
import 'package:spoonit/utils/app_theme.dart';

class AppErrorContainer extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? textColor;
  final Color? iconColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final bool showDismissButton;
  final String? dismissButtonText;
  final TextStyle? textStyle;
  final bool showIcon;

  const AppErrorContainer({
    super.key,
    required this.message,
    this.onDismiss,
    this.icon,
    this.backgroundColor,
    this.borderColor,
    this.textColor,
    this.iconColor,
    this.padding,
    this.margin,
    this.borderRadius,
    this.showDismissButton = false,
    this.dismissButtonText,
    this.textStyle,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    // Theme-aware colors
    final effectiveBackgroundColor =
        backgroundColor ?? AppTheme.errorColor.withValues(alpha: 0.1);
    final effectiveBorderColor =
        borderColor ?? AppTheme.errorColor.withValues(alpha: 0.3);
    final effectiveTextColor = textColor ?? AppTheme.errorColor;
    final effectiveIconColor = iconColor ?? AppTheme.errorColor;
    final effectiveBorderRadius = borderRadius ?? 8.0;
    final effectivePadding = padding ?? const EdgeInsets.all(12);
    final effectiveMargin = margin ?? const EdgeInsets.only(bottom: 8);

    return Container(
      margin: effectiveMargin,
      padding: effectivePadding,
      decoration: BoxDecoration(
        color: effectiveBackgroundColor,
        borderRadius: BorderRadius.circular(effectiveBorderRadius),
        border: Border.all(color: effectiveBorderColor, width: 1),
      ),
      child: Row(
        children: [
          if (showIcon) ...[
            Icon(
              icon ?? Icons.error_outline,
              color: effectiveIconColor,
              size: 20,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              message,
              style:
                  textStyle ??
                  TextStyle(
                    color: effectiveTextColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: AppTheme.primaryFontFamily,
                  ),
            ),
          ),
          if (showDismissButton && onDismiss != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(
                foregroundColor: effectiveTextColor,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                dismissButtonText ?? 'Dismiss',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppTheme.primaryFontFamily,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A specialized error container for inline form errors
class AppFormErrorContainer extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;
  final EdgeInsetsGeometry? margin;

  const AppFormErrorContainer({
    super.key,
    required this.message,
    this.onDismiss,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return AppErrorContainer(
      message: message,
      onDismiss: onDismiss,
      margin: margin ?? const EdgeInsets.only(top: 8),
      showDismissButton: onDismiss != null,
      dismissButtonText: '×',
    );
  }
}

/// A specialized error container for critical errors
class AppCriticalErrorContainer extends StatelessWidget {
  final String message;
  final String? title;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;
  final String? retryButtonText;
  final String? dismissButtonText;

  const AppCriticalErrorContainer({
    super.key,
    required this.message,
    this.title,
    this.onRetry,
    this.onDismiss,
    this.retryButtonText,
    this.dismissButtonText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.errorColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.errorColor.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error, color: AppTheme.errorColor, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title ?? 'Critical Error',
                  style: const TextStyle(
                    color: AppTheme.errorColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: AppTheme.primaryFontFamily,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              color: AppTheme.errorColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: AppTheme.primaryFontFamily,
            ),
          ),
          if (onRetry != null || onDismiss != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onDismiss != null)
                  TextButton(
                    onPressed: onDismiss,
                    child: Text(
                      dismissButtonText ?? 'Dismiss',
                      style: const TextStyle(
                        color: AppTheme.errorColor,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppTheme.primaryFontFamily,
                      ),
                    ),
                  ),
                if (onRetry != null) ...[
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.errorColor,
                      foregroundColor: AppTheme.backgroundColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      retryButtonText ?? 'Retry',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFamily: AppTheme.primaryFontFamily,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
