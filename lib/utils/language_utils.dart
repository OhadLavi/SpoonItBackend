import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoonit/providers/settings_provider.dart';

/// Language and directionality utilities for consistent RTL/LTR handling
class LanguageUtils {
  /// Check if current language is Hebrew
  static bool isHebrew(WidgetRef ref) {
    return ref.watch(settingsProvider).language == AppLanguage.hebrew;
  }

  /// Get text direction based on language
  static TextDirection getTextDirection(WidgetRef ref) {
    return isHebrew(ref) ? TextDirection.rtl : TextDirection.ltr;
  }

  /// Get text alignment based on language
  static TextAlign getTextAlignment(WidgetRef ref) {
    return isHebrew(ref) ? TextAlign.right : TextAlign.left;
  }

  /// Get cross axis alignment for columns based on language
  static CrossAxisAlignment getCrossAxisAlignment(WidgetRef ref) {
    return isHebrew(ref) ? CrossAxisAlignment.start : CrossAxisAlignment.end;
  }

  /// Get alignment for positioning widgets based on language
  static Alignment getAlignment(WidgetRef ref) {
    return isHebrew(ref) ? Alignment.centerRight : Alignment.centerLeft;
  }

  /// Get reverse alignment for positioning widgets based on language
  static Alignment getReverseAlignment(WidgetRef ref) {
    return isHebrew(ref) ? Alignment.centerLeft : Alignment.centerRight;
  }

  /// Get main axis alignment for rows based on language
  static MainAxisAlignment getMainAxisAlignment(WidgetRef ref) {
    return isHebrew(ref) ? MainAxisAlignment.end : MainAxisAlignment.start;
  }

  /// Get reverse main axis alignment for rows based on language
  static MainAxisAlignment getReverseMainAxisAlignment(WidgetRef ref) {
    return isHebrew(ref) ? MainAxisAlignment.start : MainAxisAlignment.end;
  }

  /// Get font family based on language
  static String getFontFamily(WidgetRef ref) {
    return isHebrew(ref) ? 'Heebo' : 'Assistant';
  }

  /// Get primary font family (always Assistant)
  static String getPrimaryFontFamily() {
    return 'Assistant';
  }

  /// Check if icon should be flipped for RTL (e.g., logout icon)
  static bool shouldFlipIcon(WidgetRef ref, String iconAsset) {
    if (!isHebrew(ref)) return false;

    // Icons that should be flipped for Hebrew
    const flipIcons = [
      'assets/images/logout.svg',
      'assets/images/arrow_back.svg',
      'assets/images/chevron_left.svg',
    ];

    return flipIcons.contains(iconAsset);
  }

  /// Get icon transform matrix for RTL flipping
  static Matrix4 getIconTransform(WidgetRef ref, String iconAsset) {
    if (shouldFlipIcon(ref, iconAsset)) {
      return Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0);
    }
    return Matrix4.identity();
  }

  /// Get directionality widget wrapper
  static Widget wrapWithDirectionality(WidgetRef ref, Widget child) {
    return Directionality(textDirection: getTextDirection(ref), child: child);
  }

  /// Get language-aware conditional value
  static T conditional<T>(WidgetRef ref, T hebrewValue, T englishValue) {
    return isHebrew(ref) ? hebrewValue : englishValue;
  }

  /// Get language-aware conditional widget
  static Widget conditionalWidget(
    WidgetRef ref,
    Widget hebrewWidget,
    Widget englishWidget,
  ) {
    return isHebrew(ref) ? hebrewWidget : englishWidget;
  }
}

