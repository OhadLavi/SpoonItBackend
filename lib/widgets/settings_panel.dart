import 'package:flutter/material.dart';
import 'package:recipe_keeper/widgets/settings_menu.dart';
import 'package:recipe_keeper/utils/app_theme.dart';

/// Shows the right-side settings panel used across the app.
/// Can be invoked from any screen.
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

      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
        child: Align(
          alignment: Alignment.centerRight,
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
                          color: AppTheme.backgroundColor,
                          fontFamily: AppTheme.primaryFontFamily,
                        ),
                      ),
                    ),
                    child: Directionality(
                      textDirection: TextDirection.rtl,
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
