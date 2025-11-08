import 'package:flutter/material.dart';
import 'package:spoonit/utils/app_theme.dart';

enum InfoType { success, warning, info, neutral }

class AppInfoContainer extends StatelessWidget {
  final String message;
  final InfoType type;
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
  final String? title;

  const AppInfoContainer({
    super.key,
    required this.message,
    this.type = InfoType.info,
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
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get colors based on type
    final colors = _getColorsForType(type, isDark);

    final effectiveBackgroundColor = backgroundColor ?? colors.background;
    final effectiveBorderColor = borderColor ?? colors.border;
    final effectiveTextColor = textColor ?? colors.text;
    final effectiveIconColor = iconColor ?? colors.icon;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showIcon) ...[
                Icon(
                  icon ?? _getDefaultIconForType(type),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
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
          if (title != null) ...[
            const SizedBox(height: 4),
            Text(
              title!,
              style: TextStyle(
                color: effectiveTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                fontFamily: AppTheme.primaryFontFamily,
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getDefaultIconForType(InfoType type) {
    switch (type) {
      case InfoType.success:
        return Icons.check_circle_outline;
      case InfoType.warning:
        return Icons.warning_outlined;
      case InfoType.info:
        return Icons.info_outline;
      case InfoType.neutral:
        return Icons.info_outline;
    }
  }

  _InfoColors _getColorsForType(InfoType type, bool isDark) {
    switch (type) {
      case InfoType.success:
        return _InfoColors(
          background: AppTheme.successColor.withValues(alpha: 0.1),
          border: AppTheme.successColor.withValues(alpha: 0.3),
          text: AppTheme.successColor,
          icon: AppTheme.successColor,
        );
      case InfoType.warning:
        return _InfoColors(
          background: AppTheme.warningColor.withValues(alpha: 0.1),
          border: AppTheme.warningColor.withValues(alpha: 0.3),
          text: AppTheme.warningColor,
          icon: AppTheme.warningColor,
        );
      case InfoType.info:
        return _InfoColors(
          background: AppTheme.primaryColor.withValues(alpha: 0.1),
          border: AppTheme.primaryColor.withValues(alpha: 0.3),
          text: AppTheme.primaryColor,
          icon: AppTheme.primaryColor,
        );
      case InfoType.neutral:
        return _InfoColors(
          background:
              isDark
                  ? AppTheme.darkDividerColor.withValues(alpha: 0.1)
                  : AppTheme.dividerColor.withValues(alpha: 0.1),
          border:
              isDark
                  ? AppTheme.darkDividerColor.withValues(alpha: 0.3)
                  : AppTheme.dividerColor.withValues(alpha: 0.3),
          text: isDark ? AppTheme.darkTextColor : AppTheme.textColor,
          icon: isDark ? AppTheme.darkTextColor : AppTheme.textColor,
        );
    }
  }
}

class _InfoColors {
  final Color background;
  final Color border;
  final Color text;
  final Color icon;

  const _InfoColors({
    required this.background,
    required this.border,
    required this.text,
    required this.icon,
  });
}

/// Specialized success container
class AppSuccessContainer extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;
  final String? title;
  final EdgeInsetsGeometry? margin;

  const AppSuccessContainer({
    super.key,
    required this.message,
    this.onDismiss,
    this.title,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return AppInfoContainer(
      message: message,
      type: InfoType.success,
      onDismiss: onDismiss,
      title: title,
      margin: margin,
      showDismissButton: onDismiss != null,
    );
  }
}

/// Specialized warning container
class AppWarningContainer extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;
  final String? title;
  final EdgeInsetsGeometry? margin;

  const AppWarningContainer({
    super.key,
    required this.message,
    this.onDismiss,
    this.title,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return AppInfoContainer(
      message: message,
      type: InfoType.warning,
      onDismiss: onDismiss,
      title: title,
      margin: margin,
      showDismissButton: onDismiss != null,
    );
  }
}

/// Specialized info container
class AppInfoMessageContainer extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;
  final String? title;
  final EdgeInsetsGeometry? margin;

  const AppInfoMessageContainer({
    super.key,
    required this.message,
    this.onDismiss,
    this.title,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return AppInfoContainer(
      message: message,
      type: InfoType.info,
      onDismiss: onDismiss,
      title: title,
      margin: margin,
      showDismissButton: onDismiss != null,
    );
  }
}
