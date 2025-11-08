import 'package:flutter/material.dart';
import 'package:spoonit/utils/app_theme.dart';

class AppPrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? disabledBackgroundColor;
  final Color? disabledForegroundColor;
  final double? borderRadius;
  final TextStyle? textStyle;
  final Widget? icon;
  final MainAxisAlignment? iconAlignment;
  final double? elevation;
  final Duration? loadingDuration;

  const AppPrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.width,
    this.height,
    this.padding,
    this.backgroundColor,
    this.foregroundColor,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.borderRadius,
    this.textStyle,
    this.icon,
    this.iconAlignment,
    this.elevation,
    this.loadingDuration,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = height ?? 44.0;
    final effectiveBorderRadius = borderRadius ?? 24.0;
    final effectiveElevation = elevation ?? 0.0;

    // Theme-aware colors
    final effectiveBackgroundColor = backgroundColor ?? AppTheme.primaryColor;
    final effectiveForegroundColor =
        foregroundColor ?? AppTheme.backgroundColor;
    final effectiveDisabledBackgroundColor =
        disabledBackgroundColor ?? AppTheme.primaryColor.withValues(alpha: 0.5);
    final effectiveDisabledForegroundColor =
        disabledForegroundColor ??
        AppTheme.backgroundColor.withValues(alpha: 0.7);

    final isButtonDisabled = isDisabled || isLoading || onPressed == null;

    return SizedBox(
      width: width,
      height: effectiveHeight,
      child: ElevatedButton(
        onPressed: isButtonDisabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isButtonDisabled
                  ? effectiveDisabledBackgroundColor
                  : effectiveBackgroundColor,
          foregroundColor:
              isButtonDisabled
                  ? effectiveDisabledForegroundColor
                  : effectiveForegroundColor,
          disabledBackgroundColor: effectiveDisabledBackgroundColor,
          disabledForegroundColor: effectiveDisabledForegroundColor,
          shadowColor: Colors.transparent,
          elevation: effectiveElevation,
          padding:
              padding ??
              const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(effectiveBorderRadius),
          ),
          textStyle:
              textStyle ??
              const TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
        ),
        child: _buildButtonContent(),
      ),
    );
  }

  Widget _buildButtonContent() {
    if (isLoading) {
      return _buildLoadingContent();
    }

    if (icon != null) {
      // If text is empty, show only icon
      if (text.isEmpty) {
        return icon!;
      }
      return _buildIconContent();
    }

    return Text(text);
  }

  Widget _buildLoadingContent() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              foregroundColor ?? AppTheme.backgroundColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(text),
      ],
    );
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
        Text(text),
        if (alignment == MainAxisAlignment.end) ...[
          const SizedBox(width: 8),
          icon!,
        ],
      ],
    );
  }
}

/// A specialized primary button for destructive actions
class AppDangerButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final TextStyle? textStyle;
  final Widget? icon;
  final MainAxisAlignment? iconAlignment;

  const AppDangerButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.width,
    this.height,
    this.padding,
    this.borderRadius,
    this.textStyle,
    this.icon,
    this.iconAlignment,
  });

  @override
  Widget build(BuildContext context) {
    return AppPrimaryButton(
      text: text,
      onPressed: onPressed,
      isLoading: isLoading,
      isDisabled: isDisabled,
      width: width,
      height: height,
      padding: padding,
      backgroundColor: AppTheme.errorColor,
      foregroundColor: AppTheme.backgroundColor,
      disabledBackgroundColor: AppTheme.errorColor.withValues(alpha: 0.5),
      disabledForegroundColor: AppTheme.backgroundColor.withValues(alpha: 0.7),
      borderRadius: borderRadius,
      textStyle: textStyle,
      icon: icon,
      iconAlignment: iconAlignment,
    );
  }
}

/// A specialized primary button for success actions
class AppSuccessButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final TextStyle? textStyle;
  final Widget? icon;
  final MainAxisAlignment? iconAlignment;

  const AppSuccessButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.width,
    this.height,
    this.padding,
    this.borderRadius,
    this.textStyle,
    this.icon,
    this.iconAlignment,
  });

  @override
  Widget build(BuildContext context) {
    return AppPrimaryButton(
      text: text,
      onPressed: onPressed,
      isLoading: isLoading,
      isDisabled: isDisabled,
      width: width,
      height: height,
      padding: padding,
      backgroundColor: AppTheme.successColor,
      foregroundColor: AppTheme.backgroundColor,
      disabledBackgroundColor: AppTheme.successColor.withValues(alpha: 0.5),
      disabledForegroundColor: AppTheme.backgroundColor.withValues(alpha: 0.7),
      borderRadius: borderRadius,
      textStyle: textStyle,
      icon: icon,
      iconAlignment: iconAlignment,
    );
  }
}
