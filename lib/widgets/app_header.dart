import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/widgets/settings_panel.dart';
import 'package:recipe_keeper/utils/app_theme.dart';

class AppHeader extends StatefulWidget {
  final String? title;
  final Widget? customContent;
  final VoidCallback? onProfileTap;
  final bool showBackButton;
  final VoidCallback? onBackPressed;

  const AppHeader({
    super.key,
    this.title,
    this.customContent,
    this.onProfileTap,
    this.showBackButton = false,
    this.onBackPressed,
  });

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      child: Container(
        color: AppTheme.primaryColor,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top bar: center logo (absolute), icons pinned left/right
                SizedBox(
                  height: 40,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Left: back (optional)
                      if (widget.showBackButton)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 40,
                            height: 32,
                            child: _TopIconButton(
                              icon: Icons.arrow_back,
                              onTap:
                                  widget.onBackPressed ??
                                  () => Navigator.of(context).pop(),
                            ),
                          ),
                        ),

                      // Center: logo – truly centered independent of side widgets
                      GestureDetector(
                        onTap: () => context.go('/home'),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: SizedBox(
                            height: 32,
                            child: Transform.translate(
                              // tiny down-nudge for nicer optical centering
                              offset: const Offset(0, 1),
                              child: SvgPicture.asset(
                                'assets/images/logo.svg',
                                height: 32,
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                                colorFilter: const ColorFilter.mode(
                                  AppTheme.backgroundColor,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Right: profile
                      Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: 40,
                          height: 32,
                          child: Transform.translate(
                            // Match logo's down-nudge for visual alignment
                            offset: const Offset(0, 1),
                            child: _TopProfileButton(
                              onTap:
                                  widget.onProfileTap ??
                                  () => showSettingsPanel(context),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Search or title
                if (widget.customContent != null)
                  widget.customContent!
                else if (widget.title != null)
                  Text(
                    widget.title!,
                    style: const TextStyle(
                      color: AppTheme.backgroundColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: AppTheme.primaryFontFamily,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        // 4 + 24 icon = 32 row height
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 24, color: AppTheme.backgroundColor),
      ),
    );
  }
}

class _TopProfileButton extends StatelessWidget {
  final VoidCallback onTap;

  const _TopProfileButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        // 4 + 24 icon = 32 row height
        padding: const EdgeInsets.all(4),
        child: SvgPicture.asset(
          'assets/images/profile.svg',
          width: 24,
          height: 24,
          colorFilter: const ColorFilter.mode(
            AppTheme.backgroundColor,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
