import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:recipe_keeper/providers/settings_provider.dart';

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
                            color: AppTheme.dividerColor.withOpacity(0.2),
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
    // Check if we're in English mode
    final isEnglish =
        ref.read(settingsProvider).language == AppLanguage.english;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => Directionality(
            textDirection: isEnglish ? TextDirection.ltr : TextDirection.rtl,
            child: Container(
              decoration: const BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppTranslations.getText(ref, 'add_recipe'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: AppTheme.primaryFontFamily,
                        color: AppTheme.textColor,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      leading: const Icon(
                        Icons.edit,
                        color: AppTheme.primaryColor,
                      ),
                      title: Text(
                        AppTranslations.getText(ref, 'create_new_recipe'),
                        style: const TextStyle(
                          fontFamily: AppTheme.primaryFontFamily,
                          color: AppTheme.textColor,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/add-recipe');
                      },
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.link,
                        color: AppTheme.primaryColor,
                      ),
                      title: Text(
                        AppTranslations.getText(ref, 'import_recipe'),
                        style: const TextStyle(
                          fontFamily: AppTheme.primaryFontFamily,
                          color: AppTheme.textColor,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/import-recipe');
                      },
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.camera_alt,
                        color: AppTheme.primaryColor,
                      ),
                      title: Text(
                        AppTranslations.getText(ref, 'scan_recipe'),
                        style: const TextStyle(
                          fontFamily: AppTheme.primaryFontFamily,
                          color: AppTheme.textColor,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/scan-recipe');
                      },
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

class CurvedBottomNavPainter extends CustomPainter {
  CurvedBottomNavPainter({
    this.barColor = AppTheme.cardColor,
    this.fabDiameter = 56, // your FAB is 56 → radius 28
    this.notchDepth, // how deep the valley dips below the top edge
    this.shoulder = 22, // how wide the rounded “shoulders” are
    this.smoothness = 0.45, // 0.3–0.6 looks nice; controls curvature tension
  });

  final Color barColor;
  final double fabDiameter;
  final double shoulder;
  final double smoothness;
  final double? notchDepth; // if null → computed from fabDiameter

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = barColor
          ..style = PaintingStyle.fill;

    final cX = size.width / 2; // notch center on X
    final topY = 0.0;

    // Valley depth: a bit deeper than FAB radius to expose a gap under the FAB,
    // like in your reference image.
    final depth = notchDepth ?? (fabDiameter / 2 + 8); // 28 + 8 = 36

    // Horizontal half-width of the valley from center to where top turns down.
    final halfNotchW = fabDiameter / 2 + shoulder; // 28 + 22 = 50

    final path = Path();

    // Start at bottom-left and go up the left edge
    path.moveTo(0, size.height);
    path.lineTo(0, topY);

    // Flat top until the left shoulder start
    path.lineTo(cX - halfNotchW, topY);

    // Left rounded shoulder → valley bottom (cubic for smoothness)
    // Control points are tuned to get the smooth “U” shape.
    path.cubicTo(
      cX - halfNotchW * (1 - smoothness),
      topY, // cp1: pull slightly inward
      cX - fabDiameter * 0.55,
      depth, // cp2: aim toward bottom
      cX,
      depth, // end at valley bottom
    );

    // Valley bottom → right shoulder (mirror of the left side)
    path.cubicTo(
      cX + fabDiameter * 0.55,
      depth, // cp1
      cX + halfNotchW * (1 - smoothness),
      topY, // cp2
      cX + halfNotchW,
      topY, // end at top
    );

    // Flat top to right edge, then close the shape
    path.lineTo(size.width, topY);
    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CurvedBottomNavPainter old) {
    return old.barColor != barColor ||
        old.fabDiameter != fabDiameter ||
        old.notchDepth != notchDepth ||
        old.shoulder != shoulder ||
        old.smoothness != smoothness;
  }
}
