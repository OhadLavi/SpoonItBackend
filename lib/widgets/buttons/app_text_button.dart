import 'package:flutter/material.dart';
import 'package:spoonit/utils/app_theme.dart';

class AppTextButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isDisabled;
  final Color? textColor;
  final Color? disabledTextColor;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final Widget? icon;
  final MainAxisAlignment? iconAlignment;
  final bool underline;

  const AppTextButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isDisabled = false,
    this.textColor,
    this.disabledTextColor,
    this.textStyle,
    this.padding,
    this.borderRadius,
    this.icon,
    this.iconAlignment,
    this.underline = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isButtonDisabled = isDisabled || onPressed == null;

    // Theme-aware colors
    final effectiveTextColor =
        textColor ?? (isDark ? AppTheme.darkTextColor : AppTheme.textColor);
    final effectiveDisabledTextColor =
        disabledTextColor ?? effectiveTextColor.withValues(alpha: 0.5);

    return TextButton(
      onPressed: isButtonDisabled ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor:
            isButtonDisabled ? effectiveDisabledTextColor : effectiveTextColor,
        disabledForegroundColor: effectiveDisabledTextColor,
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape:
            borderRadius != null
                ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(borderRadius!),
                )
                : null,
        textStyle:
            textStyle ??
            TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              decoration: underline ? TextDecoration.underline : null,
            ),
      ),
      child: _buildButtonContent(),
    );
  }

  Widget _buildButtonContent() {
    if (icon != null) {
      return _buildIconContent();
    }

    return Text(text);
  }

  Widget _buildIconContent() {
    final alignment = iconAlignment ?? MainAxisAlignment.center;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: alignment,
      children: [
        if (alignment == MainAxisAlignment.start ||
            alignment == MainAxisAlignment.center) ...[
          icon!,
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        if (alignment == MainAxisAlignment.end) ...[
          const SizedBox(width: 8),
          icon!,
        ],
      ],
    );
  }
}

/// A specialized text button for primary actions
class AppPrimaryTextButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isDisabled;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final Widget? icon;
  final MainAxisAlignment? iconAlignment;
  final bool underline;

  const AppPrimaryTextButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isDisabled = false,
    this.textStyle,
    this.padding,
    this.borderRadius,
    this.icon,
    this.iconAlignment,
    this.underline = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppTextButton(
      text: text,
      onPressed: onPressed,
      isDisabled: isDisabled,
      textColor: AppTheme.primaryColor,
      disabledTextColor: AppTheme.primaryColor.withValues(alpha: 0.5),
      textStyle: textStyle,
      padding: padding,
      borderRadius: borderRadius,
      icon: icon,
      iconAlignment: iconAlignment,
      underline: underline,
    );
  }
}

/// A specialized text button for secondary actions
class AppSecondaryTextButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isDisabled;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final Widget? icon;
  final MainAxisAlignment? iconAlignment;
  final bool underline;

  const AppSecondaryTextButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isDisabled = false,
    this.textStyle,
    this.padding,
    this.borderRadius,
    this.icon,
    this.iconAlignment,
    this.underline = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppTextButton(
      text: text,
      onPressed: onPressed,
      isDisabled: isDisabled,
      textColor: AppTheme.secondaryTextColor,
      disabledTextColor: AppTheme.secondaryTextColor.withValues(alpha: 0.5),
      textStyle: textStyle,
      padding: padding,
      borderRadius: borderRadius,
      icon: icon,
      iconAlignment: iconAlignment,
      underline: underline,
    );
  }
}

/// A specialized text button for destructive actions
class AppDangerTextButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isDisabled;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final Widget? icon;
  final MainAxisAlignment? iconAlignment;
  final bool underline;

  const AppDangerTextButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isDisabled = false,
    this.textStyle,
    this.padding,
    this.borderRadius,
    this.icon,
    this.iconAlignment,
    this.underline = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppTextButton(
      text: text,
      onPressed: onPressed,
      isDisabled: isDisabled,
      textColor: AppTheme.errorColor,
      disabledTextColor: AppTheme.errorColor.withValues(alpha: 0.5),
      textStyle: textStyle,
      padding: padding,
      borderRadius: borderRadius,
      icon: icon,
      iconAlignment: iconAlignment,
      underline: underline,
    );
  }
}

/// A specialized text button for link-like behavior
class AppLinkButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isDisabled;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;
  final Widget? icon;
  final MainAxisAlignment? iconAlignment;

  const AppLinkButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isDisabled = false,
    this.textStyle,
    this.padding,
    this.icon,
    this.iconAlignment,
  });

  @override
  Widget build(BuildContext context) {
    return AppTextButton(
      text: text,
      onPressed: onPressed,
      isDisabled: isDisabled,
      textColor: AppTheme.primaryColor,
      disabledTextColor: AppTheme.primaryColor.withValues(alpha: 0.5),
      textStyle:
          textStyle ??
          const TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.underline,
          ),
      padding: padding,
      icon: icon,
      iconAlignment: iconAlignment,
      underline: true,
    );
  }
}
