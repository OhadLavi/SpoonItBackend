import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/widgets/settings_panel.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/translations.dart';

class AppHeader extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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
                      // Left: back (optional) or profile (for English)
                      if (showBackButton)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 40,
                            height: 32,
                            child: _TopIconButton(
                              icon:
                                  AppTranslations.getText(ref, 'home') == 'Home'
                                      ? Icons.arrow_forward
                                      : Icons.arrow_back,
                              onTap:
                                  onBackPressed ??
                                  () => Navigator.of(context).pop(),
                            ),
                          ),
                        )
                      else if (AppTranslations.getText(ref, 'home') ==
                          'Home') // English
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 40,
                            height: 32,
                            child: Transform.translate(
                              // Adjust vertical alignment to match logo text baseline
                              offset: const Offset(0, 2),
                              child: _TopProfileButton(
                                onTap:
                                    onProfileTap ??
                                    () => showSettingsPanel(context),
                              ),
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

                      // Right: profile (for Hebrew) or empty space (for English)
                      if (AppTranslations.getText(ref, 'home') !=
                          'Home') // Hebrew
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 40,
                            height: 32,
                            child: Transform.translate(
                              // Adjust vertical alignment to match logo text baseline
                              offset: const Offset(0, 2),
                              child: _TopProfileButton(
                                onTap:
                                    onProfileTap ??
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
                if (customContent != null)
                  customContent!
                else if (title != null)
                  Text(
                    title!,
                    style: const TextStyle(
                      color: AppTheme.lightAccentColor,
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
        child: Icon(icon, size: 24, color: AppTheme.lightAccentColor),
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
        // 6 + 20 icon = 32 row height (adjusted for smaller icon)
        padding: const EdgeInsets.all(6),
        child: SvgPicture.asset(
          'assets/images/profile.svg',
          width: 20,
          height: 20,
          colorFilter: const ColorFilter.mode(
            AppTheme.backgroundColor,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
