import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/widgets/settings_menu.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/providers/settings_provider.dart';

/// Shows the settings panel used across the app.
/// Slides from right in Hebrew, left in English.
void showSettingsPanel(BuildContext context) {
  final hostContext = context; // stable parent context
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    barrierColor: AppTheme.dividerColor.withOpacity(0.54),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (context, animation, __, ___) {
      final w = MediaQuery.of(context).size.width;
      final h = MediaQuery.of(context).size.height;
      final panelW = w < 520 ? 320.0 : 380.0;

      // Check if we're in English mode
      final isEnglish =
          ProviderScope.containerOf(context).read(settingsProvider).language ==
          AppLanguage.english;

      return SlideTransition(
        position: Tween<Offset>(
          begin: isEnglish ? const Offset(-1, 0) : const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
        child: Align(
          alignment: isEnglish ? Alignment.centerLeft : Alignment.centerRight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: panelW,
                height: h,
                decoration: const BoxDecoration(color: AppTheme.uiAccentColor),
                child: Material(
                  color: Colors.transparent,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      textTheme: Theme.of(context).textTheme.copyWith(
                        bodyMedium: TextStyle(
                          color: AppTheme.lightAccentColor,
                          fontFamily: AppTheme.primaryFontFamily,
                        ),
                      ),
                    ),
                    child: Directionality(
                      textDirection:
                          isEnglish ? TextDirection.ltr : TextDirection.rtl,
                      child: SettingsMenu(hostContext: hostContext),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -18,
                top: 44,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: CustomPaint(
                    size: const Size(32, 32),
                    painter: WavyButtonPainter(),
                    child: const Center(
                      child: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: AppTheme.primaryColor,
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class WavyButtonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = AppTheme.uiAccentColor
          ..style = PaintingStyle.fill;

    final path = Path();

    // Start from top-left
    path.moveTo(0, 0);

    // Create concave curve on the left edge
    path.cubicTo(
      size.width * 0.1,
      size.height * 0.2, // Control point 1
      size.width * 0.1,
      size.height * 0.8, // Control point 2
      0,
      size.height, // End at bottom-left
    );

    // Bottom edge (straight)
    path.lineTo(size.width, size.height);

    // Right edge (straight)
    path.lineTo(size.width, 0);

    // Top edge (straight)
    path.lineTo(0, 0);

    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
