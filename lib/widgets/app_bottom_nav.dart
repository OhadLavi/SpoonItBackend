import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:recipe_keeper/utils/navigation_helpers.dart';
import 'package:recipe_keeper/widgets/painters/curved_bottom_nav_painter.dart';

class AppBottomNav extends ConsumerWidget {
  final int currentIndex;

  const AppBottomNav({super.key, this.currentIndex = -1});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 88,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 60,
                child: CustomPaint(
                  painter: CurvedBottomNavPainter(),
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
                      // Empty space for FAB
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
            ),

            // FAB fully inside Stack bounds → clickable everywhere
            Positioned(
              top: 0, // no negative offset
              left: 0,
              right: 0,
              child: Center(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _showAddRecipeOptions(context, ref),
                    child: Container(
                      height: 56,
                      width: 56,
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
