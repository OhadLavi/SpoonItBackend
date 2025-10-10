import 'package:flutter/material.dart';

/// Responsive sizing utilities for consistent UI scaling
class ResponsiveUtils {
  // Breakpoint constants
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;

  /// Get breakpoint type based on screen width
  static BreakpointType getBreakpointType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) return BreakpointType.mobile;
    if (width < tabletBreakpoint) return BreakpointType.tablet;
    return BreakpointType.desktop;
  }

  /// Check if screen is mobile
  static bool isMobile(BuildContext context) {
    return getBreakpointType(context) == BreakpointType.mobile;
  }

  /// Check if screen is tablet
  static bool isTablet(BuildContext context) {
    return getBreakpointType(context) == BreakpointType.tablet;
  }

  /// Check if screen is desktop
  static bool isDesktop(BuildContext context) {
    return getBreakpointType(context) == BreakpointType.desktop;
  }

  /// Calculate responsive icon size based on screen width
  static double calculateResponsiveIconSize(
    BuildContext context, {
    double minSize = 20.0,
    double maxSize = 80.0,
    double scaleFactor = 0.10,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    return (screenWidth * scaleFactor).clamp(minSize, maxSize);
  }

  /// Calculate responsive font size based on screen width
  static double calculateResponsiveFontSize(
    BuildContext context, {
    double minSize = 12.0,
    double maxSize = 20.0,
    double scaleFactor = 0.033,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    return (screenWidth * scaleFactor).clamp(minSize, maxSize);
  }

  /// Calculate responsive spacing based on screen width
  static double calculateResponsiveSpacing(
    BuildContext context, {
    double minSpacing = 8.0,
    double maxSpacing = 32.0,
    double scaleFactor = 0.06,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    return (screenWidth * scaleFactor).clamp(minSpacing, maxSpacing);
  }

  /// Calculate responsive padding based on screen width
  static EdgeInsets calculateResponsivePadding(
    BuildContext context, {
    double minPadding = 8.0,
    double maxPadding = 24.0,
    double scaleFactor = 0.04,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = (screenWidth * scaleFactor).clamp(minPadding, maxPadding);
    return EdgeInsets.all(padding);
  }

  /// Calculate responsive margin based on screen width
  static EdgeInsets calculateResponsiveMargin(
    BuildContext context, {
    double minMargin = 4.0,
    double maxMargin = 16.0,
    double scaleFactor = 0.02,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final margin = (screenWidth * scaleFactor).clamp(minMargin, maxMargin);
    return EdgeInsets.all(margin);
  }

  /// Get responsive grid cross axis count
  static int getResponsiveGridCrossAxisCount(BuildContext context) {
    final breakpoint = getBreakpointType(context);
    switch (breakpoint) {
      case BreakpointType.mobile:
        return 2;
      case BreakpointType.tablet:
        return 3;
      case BreakpointType.desktop:
        return 4;
    }
  }

  /// Get responsive grid child aspect ratio
  static double getResponsiveGridChildAspectRatio(BuildContext context) {
    final breakpoint = getBreakpointType(context);
    switch (breakpoint) {
      case BreakpointType.mobile:
        return 0.8;
      case BreakpointType.tablet:
        return 0.85;
      case BreakpointType.desktop:
        return 0.9;
    }
  }

  /// Calculate responsive panel width
  static double calculateResponsivePanelWidth(
    BuildContext context, {
    double maxWidth = 500.0,
    double minWidth = 300.0,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < mobileBreakpoint) {
      return (screenWidth - 32.0).clamp(minWidth, maxWidth);
    }
    return maxWidth;
  }

  /// Calculate responsive icon size for auth screens
  static double calculateAuthIconSize(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth >= 1100) return 180;
    if (screenWidth >= 700) return 140;
    return 100;
  }

  /// Get responsive text style
  static TextStyle getResponsiveTextStyle(
    BuildContext context, {
    double baseFontSize = 16.0,
    FontWeight fontWeight = FontWeight.normal,
    String? fontFamily,
  }) {
    final fontSize = calculateResponsiveFontSize(
      context,
      minSize: baseFontSize * 0.8,
      maxSize: baseFontSize * 1.2,
    );

    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontFamily: fontFamily,
    );
  }

  /// Get responsive button style
  static ButtonStyle getResponsiveButtonStyle(
    BuildContext context, {
    double minHeight = 40.0,
    double maxHeight = 56.0,
    double minPadding = 12.0,
    double maxPadding = 24.0,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final height = (screenWidth * 0.05).clamp(minHeight, maxHeight);
    final padding = (screenWidth * 0.03).clamp(minPadding, maxPadding);

    return ElevatedButton.styleFrom(
      minimumSize: Size(0, height),
      padding: EdgeInsets.symmetric(
        horizontal: padding,
        vertical: padding * 0.5,
      ),
    );
  }
}

/// Breakpoint types for responsive design
enum BreakpointType { mobile, tablet, desktop }

