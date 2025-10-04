import 'package:flutter/material.dart';
import 'package:recipe_keeper/widgets/settings_menu.dart';

/// Shows the right-side settings panel used across the app.
/// Can be invoked from any screen.
void showSettingsPanel(BuildContext context) {
  final hostContext = context; // stable parent context
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    barrierColor: Colors.black54,
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
                decoration: const BoxDecoration(
                  color: Color(0xFF3A3638),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: SettingsMenu(hostContext: hostContext),
                  ),
                ),
              ),
              Positioned(
                left: -18,
                top: 12,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF7E6B),
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(12),
                        right: Radius.circular(12),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Colors.white,
                      textDirection: TextDirection.ltr,
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
