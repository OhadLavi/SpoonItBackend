import 'package:flutter/material.dart';

class AppTheme {
  // Light Theme Colors - Updated to match new app style
  static const Color primaryColor = Color(0xFFFC7562); // Peach
  static const Color accentColor = Color(0xFFFC7562); // Peach
  static const Color backgroundColor = Colors.white;
  static const Color cardColor = Color(0xFFF8F8F8); // Light Gray
  static const Color textColor = Color(0xFF6E3C3F); // Brown
  static const Color secondaryTextColor = Color(0xFF6E3C3F); // Brown
  static const Color errorColor = Color(0xFFE53935);
  static const Color successColor = Color(0xFFFC7562); // Peach
  static const Color warningColor = Color(0xFFFFA000);
  static const Color dividerColor = Color(0xFFE0E0E0);
  static const Color uiAccentColor = Color(
    0xFF3C3638,
  ); // Dark accent color for UI elements
  static const Color iconColor = Color(0xFF333333); // Dark gray for icons
  static const Color lightAccentColor = Color(
    0xFFF8F8F8,
  ); // Light accent color for UI elements
  static const Color recipeTextColor = Color(0xFF6E3C3F); // Recipe text color

  // Font Families
  static const String primaryFontFamily = 'Assistant';
  static const String secondaryFontFamily = 'Assistant';
  static const String displayFontFamily = 'Assistant';

  // Additional color utilities
  static const Color infoColor = Color(0xFFFC7562); // Peach for info messages
  static const Color loadingColor = Color(
    0xFFFC7562,
  ); // Peach for loading indicators

  // Dark Theme Colors - Updated to match new app style
  static const Color darkPrimaryColor = Color(0xFFFC7562); // New Peach
  static const Color darkAccentColor = Color(0xFFFC7562); // New Peach
  static const Color darkBackgroundColor = Color(
    0xFF171A21,
  ); // New dark background
  static const Color darkCardColor = Color(
    0xFF1e2027,
  ); // New dark color for inputs
  static const Color darkInputHoverColor = Color(
    0xFF2C2E36,
  ); // Input hover color
  static const Color darkTextColor = Color(0xFFdbc0a4);
  static const Color darkSecondaryTextColor = Color(0xFFdbc0a4);
  static const Color darkDividerColor = Color(0xFF424242);

  // Dynamic colors that automatically choose based on theme
  static Color getBackgroundColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? darkBackgroundColor : backgroundColor;
  }

  static Color getCardColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? darkCardColor : cardColor;
  }

  static Color getTextColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? darkTextColor : textColor;
  }

  static Color getSecondaryTextColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? darkSecondaryTextColor : secondaryTextColor;
  }

  static Color getDividerColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? darkDividerColor : dividerColor;
  }

  static Color getInputHoverColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? darkInputHoverColor : cardColor;
  }

  static Color getLightAccentColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? primaryColor : lightAccentColor;
  }

  // Get text style based on current theme brightness
  static TextStyle getHeadingStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: primaryFontFamily,
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: isDark ? darkTextColor : textColor,
    );
  }

  static TextStyle getSubheadingStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: primaryFontFamily,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: isDark ? darkTextColor : textColor,
    );
  }

  static TextStyle getBodyStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: primaryFontFamily,
      fontSize: 16,
      color: isDark ? darkTextColor : textColor,
    );
  }

  static TextStyle getCaptionStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: primaryFontFamily,
      fontSize: 14,
      color: isDark ? darkSecondaryTextColor : secondaryTextColor,
    );
  }

  // Legacy Text Styles (for backward compatibility)
  static final TextStyle headingStyle = TextStyle(
    fontFamily: primaryFontFamily,
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: textColor,
  );

  static final TextStyle subheadingStyle = TextStyle(
    fontFamily: primaryFontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textColor,
  );

  static final TextStyle bodyStyle = TextStyle(
    fontFamily: primaryFontFamily,
    fontSize: 16,
    color: textColor,
  );

  static final TextStyle captionStyle = TextStyle(
    fontFamily: primaryFontFamily,
    fontSize: 14,
    color: secondaryTextColor,
  );

  // Button Styles
  static final ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primaryColor,
    foregroundColor: lightAccentColor,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: TextStyle(
      fontFamily: primaryFontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
  );

  static final ButtonStyle secondaryButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: primaryColor,
    side: const BorderSide(color: primaryColor),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: TextStyle(
      fontFamily: primaryFontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
  );

  // Card Styles
  static BoxDecoration getCardDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: getCardColor(context),
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  // Legacy Card Style
  static final BoxDecoration cardDecoration = BoxDecoration(
    color: cardColor,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );

  // Input Decoration
  static InputDecoration inputDecoration(
    String label, {
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
    BuildContext? context,
  }) {
    final isDark =
        context != null && Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? darkDividerColor : dividerColor;
    final textColor = isDark ? darkSecondaryTextColor : secondaryTextColor;
    final primaryColorToUse = primaryColor; // Use same primary for both themes

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: primaryColorToUse, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: errorColor),
      ),
      labelStyle: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 16,
        color: textColor,
      ),
      hintStyle: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 16,
        color: textColor,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  // App Theme Data
  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: primaryColor,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      primary: primaryColor,
      secondary: accentColor,
      surface: backgroundColor,
      error: errorColor,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: backgroundColor,
    textTheme: const TextTheme().copyWith(
      displayLarge: headingStyle,
      displayMedium: subheadingStyle,
      bodyLarge: bodyStyle,
      bodyMedium: captionStyle,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: errorColor),
      ),
      labelStyle: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 16,
        color: secondaryTextColor,
      ),
      hintStyle: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 16,
        color: secondaryTextColor,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: lightAccentColor,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: lightAccentColor,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: primaryColor,
      unselectedItemColor: secondaryTextColor,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    dividerTheme: const DividerThemeData(color: dividerColor, thickness: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryColor,
      linearTrackColor: dividerColor,
      circularTrackColor: dividerColor,
    ),
  );

  // Dark theme
  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: darkPrimaryColor,
    colorScheme: ColorScheme.fromSeed(
      seedColor: darkPrimaryColor,
      primary: darkPrimaryColor,
      secondary: darkAccentColor,
      surface: darkBackgroundColor,
      error: errorColor,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: darkBackgroundColor,
    textTheme: const TextTheme().copyWith(
      displayLarge: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: darkTextColor,
      ),
      displayMedium: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: darkTextColor,
      ),
      bodyLarge: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 16,
        color: darkTextColor,
      ),
      bodyMedium: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 14,
        color: darkSecondaryTextColor,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: darkPrimaryColor,
        foregroundColor: lightAccentColor,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: TextStyle(
          fontFamily: primaryFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: darkPrimaryColor,
        side: const BorderSide(color: darkPrimaryColor),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: TextStyle(
          fontFamily: primaryFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkCardColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: darkDividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: darkDividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: darkPrimaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: errorColor),
      ),
      labelStyle: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 16,
        color: darkSecondaryTextColor,
      ),
      hintStyle: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 16,
        color: darkSecondaryTextColor,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    cardTheme: CardThemeData(
      color: darkCardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: darkCardColor,
      foregroundColor: darkTextColor,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: darkTextColor,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: darkCardColor,
      selectedItemColor: darkPrimaryColor,
      unselectedItemColor: darkSecondaryTextColor,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    dividerTheme: const DividerThemeData(color: darkDividerColor, thickness: 1),
    dialogTheme: const DialogThemeData(backgroundColor: darkCardColor),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: darkPrimaryColor,
      linearTrackColor: darkDividerColor,
      circularTrackColor: darkDividerColor,
    ),
  );
}
