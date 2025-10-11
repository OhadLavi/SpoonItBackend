import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/utils/translations.dart';
import 'package:spoonit/utils/navigation_helpers.dart';
import 'package:spoonit/widgets/painters/curved_bottom_nav_painter.dart';

class AppBottomNav extends ConsumerWidget {
  final int currentIndex;

  const AppBottomNav({super.key, this.currentIndex = -1});

  static const double _navHeight = 60.0;
  static const double _fabSize = 56.0;
  // Space above the painted bar to host the FAB circle so it never gets clipped
  static const double _fabOverlap = 28.0; // equals roughly _fabSize/2

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    // Use the larger of viewPadding / padding / gestureInsets to be safe across OEMs
    final double safeBottom = [
      media.padding.bottom,
      media.viewPadding.bottom,
      media.systemGestureInsets.bottom,
    ].reduce(math.max);

    // Visually continue the nav color *behind* Android’s software buttons
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        systemNavigationBarColor: AppTheme.cardColor,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );

    final double totalHeight = _navHeight + _fabOverlap + safeBottom;

    return SizedBox(
      height: totalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Painted bar + a filler that extends color into the bottom inset
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: _navHeight + safeBottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The actual curved bar
                  SizedBox(
                    height: _navHeight,
                    child: CustomPaint(
                      painter: const CurvedBottomNavPainter(),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Home
                          Expanded(
                            child: _navBarItem(
                              null,
                              AppTranslations.getText(ref, 'home'),
                              currentIndex == 0,
                              () {
                                if (currentIndex != 0) {
                                  context.go('/home');
                                }
                              },
                              ref,
                            ),
                          ),
                          // Spacer for FAB cutout
                          const SizedBox(width: 80),
                          // Shopping list
                          Expanded(
                            child: _navBarItem(
                              null,
                              AppTranslations.getText(ref, 'shopping_list_nav'),
                              currentIndex == 1,
                              () {
                                if (currentIndex != 1) {
                                  context.go('/shopping-list');
                                }
                              },
                              ref,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // This fills the OS bottom inset so the bar color “continues”
                  if (safeBottom > 0)
                    Container(height: safeBottom, color: AppTheme.cardColor),
                ],
              ),
            ),
          ),

          // Center FAB – fully inside Stack bounds → always clickable
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _showAddRecipeOptions(context, ref),
                  child: Container(
                    height: _fabSize,
                    width: _fabSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.primaryColor,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.dividerColor.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.add,
                        color: AppTheme.lightAccentColor,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navBarItem(
    IconData? icon,
    String label,
    bool selected,
    VoidCallback onTap,
    WidgetRef ref,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null)
              Icon(icon, color: AppTheme.iconColor, size: 20)
            else
              SizedBox(
                width: 20,
                height: 20,
                child: SvgPicture.asset(
                  label == AppTranslations.getText(ref, 'home')
                      ? 'assets/images/home.svg'
                      : 'assets/images/list_alt.svg',
                  colorFilter: const ColorFilter.mode(
                    AppTheme.iconColor,
                    BlendMode.srcIn,
                  ),
                  fit: BoxFit.contain,
                ),
              ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.textColor,
                fontSize: 9,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddRecipeOptions(BuildContext context, WidgetRef ref) {
    NavigationHelpers.showAddRecipeOptions(context, ref);
  }
}
