import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AuthHeader extends StatelessWidget {
  final double height;
  final Widget? child;
  const AuthHeader({Key? key, this.height = 320, this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const coralColor = Color(0xFFFF7E6B);
    return Container(
      width: double.infinity,
      height: height,
      color: coralColor,
      child: Stack(
        children: [
          // Custom cutlery SVG
          Positioned(
            top: 0,
            left: 16,
            child: SvgPicture.asset(
              'assets/images/login.svg',
              width: 300,
              height: 300,
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.4),
                BlendMode.srcIn,
              ),
            ),
          ),
          // Salt dots
          Positioned(
            top: 56,
            left: 32,
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 6,
                  color: Colors.black.withValues(alpha: 0.15),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.circle,
                  size: 6,
                  color: Colors.black.withValues(alpha: 0.10),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.circle,
                  size: 6,
                  color: Colors.black.withValues(alpha: 0.07),
                ),
              ],
            ),
          ),
          // Optional child (e.g., title/subtitle)
          if (child != null) Positioned.fill(child: child!),
        ],
      ),
    );
  }
}

class AuthPanel extends StatelessWidget {
  final Widget child;
  final double topMargin;
  const AuthPanel({Key? key, required this.child, this.topMargin = 220})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 500;
    final isWeb = width > 700;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: EdgeInsets.only(top: topMargin),
        width: isWeb ? 500 : double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 0 : (isWeb ? 0 : 0),
        ),
        child: Material(
          elevation: 6,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(40),
            topRight: Radius.circular(40),
            bottomLeft: Radius.circular(0),
            bottomRight: Radius.circular(0),
          ),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: 32,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F8F8),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(40),
                topRight: Radius.circular(40),
                bottomLeft: Radius.circular(0),
                bottomRight: Radius.circular(0),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
