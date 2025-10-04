import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;

  const AppBottomNav({super.key, this.currentIndex = -1});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 60,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Navigation bar with curved cutout
            Positioned.fill(
              child: CustomPaint(
                painter: CurvedBottomNavPainter(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Home
                    Expanded(
                      child: _navBarItem(
                        Icons.home,
                        'בית',
                        currentIndex == 0,
                        () {
                          if (currentIndex != 0) {
                            context.go('/home');
                          }
                        },
                      ),
                    ),
                    // Empty space for FAB
                    const SizedBox(width: 80),
                    // Shopping list
                    Expanded(
                      child: _navBarItem(
                        Icons.list_alt,
                        'רשימת קניות',
                        currentIndex == 1,
                        () {
                          if (currentIndex != 1) {
                            context.go('/shopping-list');
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // FAB positioned above the navigation bar
            Positioned(
              top: -28,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => _showAddRecipeOptions(context),
                  child: Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF7E6B),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.add, color: Colors.white, size: 30),
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
    IconData icon,
    String label,
    bool selected,
    VoidCallback onTap,
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
            Icon(icon, color: Colors.black, size: 20),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                color: Colors.black,
                fontSize: 9,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddRecipeOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'הוסף מתכון',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Heebo',
                        color: Color(0xFF6E3C3F),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      leading: const Icon(Icons.edit, color: Color(0xFFFF7E6B)),
                      title: const Text(
                        'צור מתכון חדש',
                        style: TextStyle(
                          fontFamily: 'Heebo',
                          color: Color(0xFF6E3C3F),
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/add-recipe');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.link, color: Color(0xFFFF7E6B)),
                      title: const Text(
                        'ייבא מקישור',
                        style: TextStyle(
                          fontFamily: 'Heebo',
                          color: Color(0xFF6E3C3F),
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
                        color: Color(0xFFFF7E6B),
                      ),
                      title: const Text(
                        'סרוק מתכון',
                        style: TextStyle(
                          fontFamily: 'Heebo',
                          color: Color(0xFF6E3C3F),
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/scan-recipe');
                      },
                    ),
                    const SizedBox(height: 10),
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
    this.barColor = const Color(0xFFF8F8F8),
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
