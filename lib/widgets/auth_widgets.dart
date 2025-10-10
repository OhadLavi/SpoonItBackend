import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:recipe_keeper/utils/app_theme.dart';

/// Top colored band used on auth screens.
class AuthHeader extends StatelessWidget {
  final double height;
  final Widget? child;
  final bool showGraphic;

  const AuthHeader({
    super.key,
    this.height = 420,
    this.child,
    this.showGraphic = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? AppTheme.darkBackgroundColor : AppTheme.primaryColor;
    final iconColor = isDark ? AppTheme.darkPrimaryColor : AppTheme.textColor;

    return Container(
      width: double.infinity,
      height: height,
      color: backgroundColor,
      child: Stack(
        children: [
          if (showGraphic) ...[
            Positioned(
              top: 0,
              left: 16,
              child: SvgPicture.asset(
                'assets/images/login.svg',
                width: 400,
                height: 400,
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              ),
            ),
            Positioned(
              top: 56,
              left: 32,
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 6,
                    color: AppTheme.dividerColor.withValues(alpha: 0.15),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.circle,
                    size: 6,
                    color: AppTheme.dividerColor.withValues(alpha: 0.10),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.circle,
                    size: 6,
                    color: AppTheme.dividerColor.withValues(alpha: 0.07),
                  ),
                ],
              ),
            ),
          ],
          if (child != null) Positioned.fill(child: child!),
        ],
      ),
    );
  }
}

/// Card container for auth forms (sits below [AuthHeader]).
class AuthPanel extends StatelessWidget {
  final Widget child;
  final double topMargin;

  const AuthPanel({super.key, required this.child, this.topMargin = 220});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 500;
    final isWeb = width > 700;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.darkCardColor : AppTheme.cardColor;

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: EdgeInsets.only(top: topMargin),
        width: isWeb ? 500 : double.infinity,
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 0 : 0),
        child: Material(
          elevation: 6,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(40),
            topRight: Radius.circular(40),
          ),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: 32,
            ),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(40),
                topRight: Radius.circular(40),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Reusable text+icon row that sits above the AuthPanel.
/// - Hebrew: text on the left, right-aligned; icon on the far right.
/// - English/others: icon on the far left; text on the right, left-aligned.
class AuthWelcomeBar extends StatelessWidget {
  final double panelWidth;
  final double topMargin;
  final bool isHebrew;
  final String titleText;
  final String subtitleText;
  final String iconAsset;
  final double? maxIconSize;

  const AuthWelcomeBar({
    super.key,
    required this.panelWidth,
    required this.topMargin,
    required this.isHebrew,
    required this.titleText,
    required this.subtitleText,
    required this.iconAsset,
    this.maxIconSize,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? AppTheme.darkPrimaryColor : AppTheme.lightAccentColor;
    final iconTint = isDark ? AppTheme.darkPrimaryColor : AppTheme.textColor;

    final screenWidth = MediaQuery.of(context).size.width;

    // Responsive bigger icon (larger than the old 64)
    double computedIcon =
        screenWidth >= 1100 ? 180 : (screenWidth >= 700 ? 140 : 100);
    if (maxIconSize != null && computedIcon > maxIconSize!) {
      computedIcon = maxIconSize!;
    }

    final textBlock = Column(
      crossAxisAlignment:
          isHebrew ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(
          titleText,
          textAlign: isHebrew ? TextAlign.left : TextAlign.right,
          style: TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitleText,
          textAlign: isHebrew ? TextAlign.left : TextAlign.right,
          style: TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            fontSize: 18,
            color: textColor,
          ),
        ),
      ],
    );

    final icon =
        iconAsset.isNotEmpty
            ? SvgPicture.asset(
              iconAsset,
              width: computedIcon,
              height: computedIcon,
              colorFilter: ColorFilter.mode(iconTint, BlendMode.srcIn),
            )
            : const SizedBox.shrink();

    // Order depends on language; spaced to the edges of the panel width
    final children =
        isHebrew
            ? <Widget>[
              if (iconAsset.isNotEmpty) ...[icon, const SizedBox(width: 16)],
              Expanded(
                child: Align(
                  alignment:
                      iconAsset.isNotEmpty
                          ? Alignment.topRight
                          : Alignment.topLeft,
                  child: textBlock,
                ),
              ),
            ]
            : <Widget>[
              // Text left side of this row (but right-aligned inside itself)
              Expanded(
                child: Align(
                  alignment:
                      iconAsset.isNotEmpty
                          ? Alignment.topLeft
                          : Alignment.topRight,
                  child: textBlock,
                ),
              ),
              if (iconAsset.isNotEmpty) ...[const SizedBox(width: 16), icon],
            ];

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: panelWidth,
        margin: EdgeInsets.only(top: topMargin),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          // Force LTR layout here so our conditional ordering is deterministic
          textDirection: TextDirection.ltr,
          children: children,
        ),
      ),
    );
  }
}
