import 'package:flutter/material.dart';
import 'package:recipe_keeper/utils/app_theme.dart';

/// Curved bottom navigation painter with FAB notch
class CurvedBottomNavPainter extends CustomPainter {
  final Color barColor;
  final double fabDiameter;
  final double shoulder;
  final double smoothness;
  final double? notchDepth;

  const CurvedBottomNavPainter({
    this.barColor = AppTheme.cardColor,
    this.fabDiameter = 56,
    this.shoulder = 22,
    this.smoothness = 0.45,
    this.notchDepth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = barColor
          ..style = PaintingStyle.fill;

    final cX = size.width / 2; // notch center on X
    final topY = 0.0;

    // Valley depth: a bit deeper than FAB radius to expose a gap under the FAB
    final depth = notchDepth ?? (fabDiameter / 2 + 8); // 28 + 8 = 36

    // Horizontal half-width of the valley from center to where top turns down
    final halfNotchW = fabDiameter / 2 + shoulder; // 28 + 22 = 50

    final path = Path();

    // Start at bottom-left and go up the left edge
    path.moveTo(0, size.height);
    path.lineTo(0, topY);

    // Flat top until the left shoulder start
    path.lineTo(cX - halfNotchW, topY);

    // Left rounded shoulder → valley bottom (cubic for smoothness)
    // Control points are tuned to get the smooth "U" shape
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
  bool shouldRepaint(covariant CurvedBottomNavPainter oldDelegate) {
    return oldDelegate.barColor != barColor ||
        oldDelegate.fabDiameter != fabDiameter ||
        oldDelegate.notchDepth != notchDepth ||
        oldDelegate.shoulder != shoulder ||
        oldDelegate.smoothness != smoothness;
  }
}

