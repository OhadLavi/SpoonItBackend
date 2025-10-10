import 'package:flutter/material.dart';
import 'package:recipe_keeper/utils/app_theme.dart';

/// Wavy button painter for custom shaped buttons
class WavyButtonPainter extends CustomPainter {
  final Color color;
  final double curveStart;
  final double curveEnd;
  final double controlPoint1;
  final double controlPoint2;

  const WavyButtonPainter({
    this.color = AppTheme.uiAccentColor,
    this.curveStart = 0.1,
    this.curveEnd = 0.1,
    this.controlPoint1 = 0.2,
    this.controlPoint2 = 0.8,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    final path = Path();

    // Start from top-left
    path.moveTo(0, 0);

    // Create concave curve on the left edge
    path.cubicTo(
      size.width * curveStart,
      size.height * controlPoint1, // Control point 1
      size.width * curveStart,
      size.height * controlPoint2, // Control point 2
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
  bool shouldRepaint(covariant WavyButtonPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.curveStart != curveStart ||
        oldDelegate.curveEnd != curveEnd ||
        oldDelegate.controlPoint1 != controlPoint1 ||
        oldDelegate.controlPoint2 != controlPoint2;
  }
}

