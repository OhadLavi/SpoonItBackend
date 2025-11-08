import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/utils/language_utils.dart';

class AppTextField extends ConsumerWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final String? prefixSvgAsset;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function()? onTap;
  final void Function(String)? onFieldSubmitted;
  final bool readOnly;
  final int? maxLines;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry? contentPadding;
  final bool enabled;
  final String? errorText;
  final Color? fillColor;
  final Color? borderColor;
  final double? borderRadius;
  final bool autofocus;
  final String? name;
  final TextAlign? textAlignOverride;
  final TextDirection? textDirectionOverride;
  final void Function()? onPrefixIconTap;

  const AppTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.prefixSvgAsset,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
    this.onChanged,
    this.onTap,
    this.onFieldSubmitted,
    this.readOnly = false,
    this.maxLines = 1,
    this.maxLength,
    this.textInputAction,
    this.focusNode,
    this.contentPadding,
    this.enabled = true,
    this.errorText,
    this.fillColor,
    this.borderColor,
    this.borderRadius,
    this.autofocus = false,
    this.name,
    this.textAlignOverride,
    this.textDirectionOverride,
    this.onPrefixIconTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isHebrew = LanguageUtils.isHebrew(ref);

    // Determine text alignment and direction
    final textAlign = isHebrew ? TextAlign.right : TextAlign.left;
    final textDirection = isHebrew ? TextDirection.rtl : TextDirection.ltr;

    // Theme-aware colors
    final effectiveFillColor =
        fillColor ??
        (isDark ? AppTheme.darkCardColor : AppTheme.backgroundColor);
    final effectiveBorderColor =
        borderColor ??
        (isDark ? AppTheme.darkDividerColor : AppTheme.dividerColor);
    final effectiveBorderRadius = borderRadius ?? 24.0;

    // Content padding
    final effectiveContentPadding =
        contentPadding ??
        const EdgeInsets.symmetric(horizontal: 20, vertical: 18);

    // Generate unique name from hint text if not provided
    final String fieldName = name ?? hintText?.replaceAll(' ', '_').toLowerCase() ?? 'text_field_${DateTime.now().millisecondsSinceEpoch}';
    
    if (kDebugMode && onTap != null) {
      developer.log('AppTextField created: name=$fieldName, enabled=$enabled', name: 'AppTextField');
    }

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      onChanged: (value) {
        if (kDebugMode) {
          developer.log('TextField changed: name=$fieldName, value=$value', name: 'AppTextField');
        }
        onChanged?.call(value);
      },
      onTap: () {
        if (kDebugMode) {
          developer.log('TextField tapped: name=$fieldName', name: 'AppTextField');
        }
        onTap?.call();
      },
      onFieldSubmitted: onFieldSubmitted,
      readOnly: readOnly,
      maxLines: maxLines,
      maxLength: maxLength,
      textInputAction: textInputAction,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      textAlign: textAlignOverride ?? textAlign, // Use override if provided, otherwise use language-based alignment
      textDirection: textDirectionOverride ?? textDirection, // Use override if provided, otherwise use language-based direction
      style: TextStyle(
        color: isDark ? AppTheme.darkTextColor : AppTheme.textColor,
        fontWeight: FontWeight.w300,
        height: 1.2, // Ensure proper vertical alignment
      ),
      decoration: InputDecoration(
        semanticCounterText: fieldName, // For accessibility
        counterText: '', // Hide counter if maxLength is set
        hintText: hintText,
        labelText: labelText,
        hintStyle: TextStyle(
          color: isDark ? AppTheme.darkTextColor : AppTheme.textColor,
          fontWeight: FontWeight.w300,
          height: 1.2, // Ensure proper vertical alignment
        ),
        labelStyle: TextStyle(
          color: isDark ? AppTheme.darkTextColor : AppTheme.textColor,
          fontWeight: FontWeight.w300,
        ),
        prefixIcon: _buildPrefixIcon(),
        suffixIcon: suffixIcon,
        errorText: errorText,
        errorStyle: const TextStyle(
          color: AppTheme.errorColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: effectiveFillColor,
        contentPadding: effectiveContentPadding,
        isDense: true, // Reduce overall height
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(effectiveBorderRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(effectiveBorderRadius),
          borderSide: BorderSide(color: effectiveBorderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(effectiveBorderRadius),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(effectiveBorderRadius),
          borderSide: const BorderSide(color: AppTheme.errorColor, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(effectiveBorderRadius),
          borderSide: const BorderSide(color: AppTheme.errorColor, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(effectiveBorderRadius),
          borderSide: BorderSide(
            color: effectiveBorderColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
    );
  }

  Widget? _buildPrefixIcon() {
    Widget iconWidget;
    if (prefixSvgAsset != null) {
      iconWidget = Padding(
        padding: const EdgeInsets.all(12.0),
        child: SvgPicture.asset(
          prefixSvgAsset!,
          width: 18,
          height: 18,
          colorFilter: const ColorFilter.mode(
            AppTheme.textColor,
            BlendMode.srcIn,
          ),
        ),
      );
    } else if (prefixIcon != null) {
      iconWidget = Padding(
        padding: const EdgeInsets.all(12.0),
        child: Icon(prefixIcon!, size: 18, color: AppTheme.textColor),
      );
    } else {
      return null;
    }
    
    if (onPrefixIconTap != null) {
      return InkWell(
        onTap: onPrefixIconTap,
        borderRadius: BorderRadius.circular(8),
        child: iconWidget,
      );
    }
    return iconWidget;
  }
}
