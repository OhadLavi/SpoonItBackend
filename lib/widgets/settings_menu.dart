import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'dart:developer' as developer;

class SettingsMenu extends ConsumerWidget {
  const SettingsMenu({super.key, required this.hostContext});
  final BuildContext hostContext;

  // MUST match your menu's background EXACTLY.
  // If your panel uses a different shade, update this hex.
  static const Color kMenuBg = AppTheme.uiAccentColor;
  static const Color kAccent = AppTheme.primaryColor; // chevron color

  void _closeAndGo(String route) {
    Navigator.of(hostContext, rootNavigator: true).pop();
    GoRouter.of(hostContext).go(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _buildSettingsHeader(context, ref),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Divider(
            color: AppTheme.lightAccentColor,
            thickness: 0.5,
            height: 4,
          ),
        ),
        Expanded(child: _buildSettingsMenu(context, ref)),
      ],
    );
  }

  Widget _buildSettingsHeader(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final name = authState.user?.displayName.trim();
    final email = authState.user?.email.trim();

    // Debug logging
    developer.log(
      'SettingsMenu: Auth State: ${authState.status}',
      name: 'SettingsMenu',
    );
    developer.log(
      'SettingsMenu: User: ${authState.user}',
      name: 'SettingsMenu',
    );
    developer.log('SettingsMenu: Name: $name', name: 'SettingsMenu');
    developer.log('SettingsMenu: Email: $email', name: 'SettingsMenu');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => _closeAndGo('/profile'),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Text(
                (name?.isNotEmpty ?? false) ? name! : 'משתמש',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 34.58,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppTheme.primaryFontFamily,
                  color: AppTheme.lightAccentColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            email ?? '',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 17.29,
              fontFamily: AppTheme.primaryFontFamily,
              color: kAccent,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsMenu(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildSettingsMenuItem(
          svgAsset: 'assets/images/profile.svg',
          title: 'החשבון שלי',
          onTap: () => _closeAndGo('/profile'),
        ),
        _buildSettingsMenuItem(
          svgAsset: 'assets/images/home.svg',
          title: 'המתכונים שלי',
          onTap: () => _closeAndGo('/my-recipes'),
        ),
        _buildSettingsMenuItem(
          svgAsset: 'assets/images/list_alt.svg',
          title: 'רשימת הקניות',
          onTap: () => _closeAndGo('/shopping-list'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 28, 12),
          child: Divider(
            color: AppTheme.lightAccentColor.withValues(alpha: 0.24),
            thickness: 0.5,
            height: 4,
          ),
        ),
        _buildSettingsMenuItem(
          svgAsset: 'assets/images/help_outline.svg',
          title: 'תמיכה',
          onTap: () => _closeAndGo('/support'),
        ),
        _buildSettingsMenuItem(
          svgAsset: 'assets/images/article_outline.svg',
          title: 'תנאים והגנת פרטיות',
          onTap: () => _closeAndGo('/terms-privacy'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 28, 12),
          child: Divider(
            color: AppTheme.lightAccentColor.withValues(alpha: 0.24),
            thickness: 0.5,
            height: 4,
          ),
        ),
        _buildSettingsMenuItem(
          svgAsset: 'assets/images/logout.svg',
          title: 'התנתקות',
          onTap: () async {
            final navigator = Navigator.of(hostContext, rootNavigator: true);
            final router = GoRouter.of(hostContext);
            navigator.pop();
            await ref.read(authProvider.notifier).signOut();
            router.go('/login');
          },
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildSettingsMenuItem({
    IconData? icon,
    String? svgAsset,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 28, 32),
        child: Row(
          children: [
            if (svgAsset != null)
              SizedBox(
                width: 20,
                height: 20,
                child: SvgPicture.asset(
                  svgAsset,
                  colorFilter: ColorFilter.mode(
                    AppTheme.lightAccentColor.withValues(alpha: 0.6),
                    BlendMode.srcIn,
                  ),
                  fit: BoxFit.contain,
                ),
              )
            else if (icon != null)
              Icon(
                icon,
                size: 20,
                color: AppTheme.lightAccentColor,
                textDirection: TextDirection.ltr,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 18,
                  color: AppTheme.lightAccentColor,
                  fontWeight: FontWeight.w400,
                  fontFamily: AppTheme.primaryFontFamily,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
