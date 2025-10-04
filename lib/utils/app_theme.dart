import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Light Theme Colors - Updated to match new app style
  static const Color primaryColor = Color(0xFFFF7E6B); // Peach/Coral
  static const Color lightBlueColor = Colors.lightBlue;
  static const Color accentColor = Color(0xFFFF7E6B); // Peach/Coral
  static const Color backgroundColor = Colors.white;
  static const Color cardColor = Color(0xFFF8F8F8); // Light gray
  static const Color textColor = Color(0xFF6E3C3F); // Dark reddish-brown
  static const Color secondaryTextColor = Color(
    0xFF6E3C3F,
  ); // Dark reddish-brown with opacity
  static const Color errorColor = Color(0xFFE53935);
  static const Color successColor = Color(0xFFFF7E6B); // Peach/Coral
  static const Color warningColor = Color(0xFFFFA000);
  static const Color dividerColor = Color(0xFFE0E0E0);

  // Dark Theme Colors - Updated to match new app style
  static const Color darkPrimaryColor = Color(0xFFFF7E6B); // Peach/Coral
  static const Color darkAccentColor = Color(0xFFFF7E6B); // Peach/Coral
  static const Color darkBackgroundColor = Color(0xFF121212);
  static const Color darkCardColor = Color(0xFF1E1E1E);
  static const Color darkTextColor = Color(0xFFEEEEEE);
  static const Color darkSecondaryTextColor = Color(0xFFB0B0B0);
  static const Color darkDividerColor = Color(0xFF424242);

  // Get text style based on current theme brightness
  static TextStyle getHeadingStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GoogleFonts.heebo(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: isDark ? darkTextColor : textColor,
    );
  }

  static TextStyle getSubheadingStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GoogleFonts.heebo(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: isDark ? darkTextColor : textColor,
    );
  }

  static TextStyle getBodyStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GoogleFonts.heebo(
      fontSize: 16,
      color: isDark ? darkTextColor : textColor,
    );
  }

  static TextStyle getCaptionStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GoogleFonts.heebo(
      fontSize: 14,
      color: isDark ? darkSecondaryTextColor : secondaryTextColor,
    );
  }

  // Legacy Text Styles (for backward compatibility)
  static final TextStyle headingStyle = GoogleFonts.heebo(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: textColor,
  );

  static final TextStyle subheadingStyle = GoogleFonts.heebo(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textColor,
  );

  static final TextStyle bodyStyle = GoogleFonts.heebo(
    fontSize: 16,
    color: textColor,
  );

  static final TextStyle captionStyle = GoogleFonts.heebo(
    fontSize: 14,
    color: secondaryTextColor,
  );

  // Button Styles
  static final ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primaryColor,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: GoogleFonts.heebo(fontSize: 16, fontWeight: FontWeight.w600),
  );

  static final ButtonStyle secondaryButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: primaryColor,
    side: const BorderSide(color: primaryColor),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: GoogleFonts.heebo(fontSize: 16, fontWeight: FontWeight.w600),
  );

  // Card Styles
  static BoxDecoration getCardDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? darkCardColor : cardColor,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
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
        color: Colors.black.withOpacity(0.05),
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
      labelStyle: GoogleFonts.heebo(fontSize: 16, color: textColor),
      hintStyle: GoogleFonts.heebo(fontSize: 16, color: textColor),
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
      background: backgroundColor,
      error: errorColor,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: backgroundColor,
    textTheme: GoogleFonts.heeboTextTheme(
      const TextTheme().copyWith(
        displayLarge: headingStyle,
        displayMedium: subheadingStyle,
        bodyLarge: bodyStyle,
        bodyMedium: captionStyle,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButtonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: secondaryButtonStyle),
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
      labelStyle: GoogleFonts.heebo(fontSize: 16, color: secondaryTextColor),
      hintStyle: GoogleFonts.heebo(fontSize: 16, color: secondaryTextColor),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    cardTheme: CardTheme(
      color: cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.heebo(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
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
  );

  // Dark theme
  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: darkPrimaryColor,
    colorScheme: ColorScheme.fromSeed(
      seedColor: darkPrimaryColor,
      primary: darkPrimaryColor,
      secondary: darkAccentColor,
      background: darkBackgroundColor,
      error: errorColor,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: darkBackgroundColor,
    textTheme: GoogleFonts.heeboTextTheme(
      const TextTheme().copyWith(
        displayLarge: GoogleFonts.heebo(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: darkTextColor,
        ),
        displayMedium: GoogleFonts.heebo(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: darkTextColor,
        ),
        bodyLarge: GoogleFonts.heebo(fontSize: 16, color: darkTextColor),
        bodyMedium: GoogleFonts.heebo(
          fontSize: 14,
          color: darkSecondaryTextColor,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: darkPrimaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.heebo(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: darkPrimaryColor,
        side: const BorderSide(color: darkPrimaryColor),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.heebo(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
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
      labelStyle: GoogleFonts.heebo(
        fontSize: 16,
        color: darkSecondaryTextColor,
      ),
      hintStyle: GoogleFonts.heebo(fontSize: 16, color: darkSecondaryTextColor),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    cardTheme: CardTheme(
      color: darkCardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: darkCardColor,
      foregroundColor: darkTextColor,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.heebo(
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
  );
}
