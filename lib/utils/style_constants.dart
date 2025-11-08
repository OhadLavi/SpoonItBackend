import 'package:flutter/material.dart';
import 'package:spoonit/utils/app_theme.dart';

/// Style Constants for consistent styling across the application
///
/// This file centralizes all styling values to ensure:
/// - Consistent design system
/// - Easy theme updates
/// - No hard-coded values in UI components
/// - Maintainable styling

class StyleConstants {
  // Spacing
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;
  static const double spacingXXL = 48.0;

  // Border Radius
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 16.0;
  static const double radiusXL = 24.0;
  static const double radiusXXL = 32.0;

  // Button Heights
  static const double buttonHeightS = 32.0;
  static const double buttonHeightM = 44.0;
  static const double buttonHeightL = 56.0;
  static const double buttonHeightXL = 64.0;

  // Icon Sizes
  static const double iconSizeS = 16.0;
  static const double iconSizeM = 24.0;
  static const double iconSizeL = 32.0;
  static const double iconSizeXL = 48.0;
  static const double iconSizeXXL = 64.0;

  // Font Sizes
  static const double fontSizeXS = 10.0;
  static const double fontSizeS = 12.0;
  static const double fontSizeM = 14.0;
  static const double fontSizeL = 16.0;
  static const double fontSizeXL = 18.0;
  static const double fontSizeXXL = 20.0;
  static const double fontSizeHeading = 24.0;
  static const double fontSizeTitle = 28.0;

  // Container Heights
  static const double containerHeightS = 40.0;
  static const double containerHeightM = 48.0;
  static const double containerHeightL = 56.0;
  static const double containerHeightXL = 64.0;

  // Form Field Styles
  static const double formFieldHeight = 56.0;
  static const double formFieldBorderRadius = 12.0;
  static const double formFieldBorderWidth = 1.0;
  static const double formFieldFocusedBorderWidth = 2.0;

  // Card Styles
  static const double cardBorderRadius = 12.0;
  static const double cardElevation = 2.0;
  static const double cardShadowBlur = 4.0;
  static const double cardShadowSpread = 1.0;

  // Animation Durations
  static const Duration animationFast = Duration(milliseconds: 150);
  static const Duration animationNormal = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);

  // Screen Breakpoints
  static const double mobileBreakpoint = 500.0;
  static const double tabletBreakpoint = 768.0;
  static const double desktopBreakpoint = 1024.0;

  // Padding
  static const EdgeInsets paddingXS = EdgeInsets.all(spacingXS);
  static const EdgeInsets paddingS = EdgeInsets.all(spacingS);
  static const EdgeInsets paddingM = EdgeInsets.all(spacingM);
  static const EdgeInsets paddingL = EdgeInsets.all(spacingL);
  static const EdgeInsets paddingXL = EdgeInsets.all(spacingXL);

  // Horizontal Padding
  static const EdgeInsets paddingHorizontalS = EdgeInsets.symmetric(
    horizontal: spacingS,
  );
  static const EdgeInsets paddingHorizontalM = EdgeInsets.symmetric(
    horizontal: spacingM,
  );
  static const EdgeInsets paddingHorizontalL = EdgeInsets.symmetric(
    horizontal: spacingL,
  );
  static const EdgeInsets paddingHorizontalXL = EdgeInsets.symmetric(
    horizontal: spacingXL,
  );

  // Vertical Padding
  static const EdgeInsets paddingVerticalS = EdgeInsets.symmetric(
    vertical: spacingS,
  );
  static const EdgeInsets paddingVerticalM = EdgeInsets.symmetric(
    vertical: spacingM,
  );
  static const EdgeInsets paddingVerticalL = EdgeInsets.symmetric(
    vertical: spacingL,
  );
  static const EdgeInsets paddingVerticalXL = EdgeInsets.symmetric(
    vertical: spacingXL,
  );

  // Common Box Shadows
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: AppTheme.secondaryTextColor.withValues(alpha: 0.1),
      spreadRadius: cardShadowSpread,
      blurRadius: cardShadowBlur,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get buttonShadow => [
    BoxShadow(
      color: AppTheme.primaryColor.withValues(alpha: 0.3),
      spreadRadius: 0,
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: AppTheme.secondaryTextColor.withValues(alpha: 0.15),
      spreadRadius: 0,
      blurRadius: 12,
      offset: const Offset(0, 6),
    ),
  ];

  // Common Border Radius
  static const BorderRadius borderRadiusS = BorderRadius.all(
    Radius.circular(radiusS),
  );
  static const BorderRadius borderRadiusM = BorderRadius.all(
    Radius.circular(radiusM),
  );
  static const BorderRadius borderRadiusL = BorderRadius.all(
    Radius.circular(radiusL),
  );
  static const BorderRadius borderRadiusXL = BorderRadius.all(
    Radius.circular(radiusXL),
  );

  // Form Field Decoration
  static InputDecoration get formFieldDecoration => InputDecoration(
    contentPadding: const EdgeInsets.symmetric(
      horizontal: spacingM,
      vertical: spacingM,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(formFieldBorderRadius),
      borderSide: BorderSide(
        color: AppTheme.secondaryTextColor.withValues(alpha: 0.3),
        width: formFieldBorderWidth,
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(formFieldBorderRadius),
      borderSide: BorderSide(
        color: AppTheme.secondaryTextColor.withValues(alpha: 0.3),
        width: formFieldBorderWidth,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(formFieldBorderRadius),
      borderSide: const BorderSide(
        color: AppTheme.primaryColor,
        width: formFieldFocusedBorderWidth,
      ),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(formFieldBorderRadius),
      borderSide: const BorderSide(
        color: AppTheme.errorColor,
        width: formFieldBorderWidth,
      ),
    ),
  );

  // Button Styles
  static ButtonStyle get primaryButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: AppTheme.primaryColor,
    foregroundColor: AppTheme.lightAccentColor,
    elevation: 2,
    shadowColor: AppTheme.primaryColor.withValues(alpha: 0.3),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusXL),
    ),
    minimumSize: const Size(0, buttonHeightM),
    padding: const EdgeInsets.symmetric(
      horizontal: spacingL,
      vertical: spacingM,
    ),
  );

  static ButtonStyle get secondaryButtonStyle => OutlinedButton.styleFrom(
    foregroundColor: AppTheme.primaryColor,
    side: const BorderSide(color: AppTheme.primaryColor),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusXL),
    ),
    minimumSize: const Size(0, buttonHeightM),
    padding: const EdgeInsets.symmetric(
      horizontal: spacingL,
      vertical: spacingM,
    ),
  );

  // Text Styles
  static TextStyle get headingStyle => const TextStyle(
    fontSize: fontSizeHeading,
    fontWeight: FontWeight.bold,
    fontFamily: AppTheme.primaryFontFamily,
    color: AppTheme.textColor,
  );

  static TextStyle get subheadingStyle => const TextStyle(
    fontSize: fontSizeXL,
    fontWeight: FontWeight.w600,
    fontFamily: AppTheme.primaryFontFamily,
    color: AppTheme.textColor,
  );

  static TextStyle get bodyStyle => const TextStyle(
    fontSize: fontSizeL,
    fontWeight: FontWeight.normal,
    fontFamily: AppTheme.primaryFontFamily,
    color: AppTheme.textColor,
  );

  static TextStyle get captionStyle => const TextStyle(
    fontSize: fontSizeM,
    fontWeight: FontWeight.normal,
    fontFamily: AppTheme.secondaryFontFamily,
    color: AppTheme.secondaryTextColor,
  );

  // Responsive Helpers
  static EdgeInsets getResponsivePadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) {
      return paddingM;
    } else if (width < tabletBreakpoint) {
      return paddingL;
    } else {
      return paddingXL;
    }
  }

  static double getResponsiveFontSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) {
      return baseSize;
    } else if (width < tabletBreakpoint) {
      return baseSize * 1.1;
    } else {
      return baseSize * 1.2;
    }
  }
}





