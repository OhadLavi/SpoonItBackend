import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CategoryIconService {
  static const Map<String, String> _iconPaths = {
    'bread': 'assets/images/categories/bread.svg',
    'cookies':
        'assets/images/categories/coockies.svg', // Note: keeping original typo in filename
    'cakes': 'assets/images/categories/cakes.svg',
    'salads': 'assets/images/categories/salads.svg',
    'sides': 'assets/images/categories/sides.svg',
    'main': 'assets/images/categories/main.svg',
    'pastries': 'assets/images/categories/pastries.svg',
  };

  static const Map<String, String> _defaultCategoryMapping = {
    'מאפים': 'pastries',
    'עיקריות': 'main',
    'תוספות': 'sides',
    'עוגיות': 'cookies',
    'עוגות': 'cakes',
    'סלטים': 'salads',
    'לחמים': 'bread',
  };

  /// Get the SVG icon widget for a category
  static Widget getCategoryIcon(
    String categoryName, {
    double size = 40,
    Color? color,
  }) {
    final iconKey = _defaultCategoryMapping[categoryName] ?? 'main';
    final iconPath = _iconPaths[iconKey] ?? _iconPaths['main']!;

    return SvgPicture.asset(
      iconPath,
      width: size,
      height: size,
      // Remove colorFilter to show original SVG colors
      // colorFilter: color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null,
    );
  }

  /// Get the SVG icon widget by icon key
  static Widget getIconByKey(String iconKey, {double size = 40, Color? color}) {
    final iconPath = _iconPaths[iconKey] ?? _iconPaths['main']!;

    return SvgPicture.asset(
      iconPath,
      width: size,
      height: size,
      // Remove colorFilter to show original SVG colors
      // colorFilter: color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null,
    );
  }

  /// Get all available icon keys
  static List<String> getAvailableIconKeys() {
    return _iconPaths.keys.toList();
  }

  /// Get icon path by key
  static String? getIconPath(String iconKey) {
    return _iconPaths[iconKey];
  }

  /// Get icon key by category name
  static String getIconKeyForCategory(String categoryName) {
    return _defaultCategoryMapping[categoryName] ?? 'main';
  }
}
