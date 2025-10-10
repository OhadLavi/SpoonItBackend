import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/providers/settings_provider.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'dart:developer' as developer;
import 'package:recipe_keeper/utils/translations.dart';

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

    // Check if we're in English mode
    final isEnglish =
        ref.read(settingsProvider).language == AppLanguage.english;

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
                (name?.isNotEmpty ?? false)
                    ? name!
                    : AppTranslations.getText(ref, 'user'),
                textAlign: isEnglish ? TextAlign.left : TextAlign.right,
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
            textAlign: isEnglish ? TextAlign.left : TextAlign.right,
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
          title: AppTranslations.getText(ref, 'my_account'),
          onTap: () => _closeAndGo('/profile'),
          ref: ref,
        ),
        _buildSettingsMenuItem(
          svgAsset: 'assets/images/home.svg',
          title: AppTranslations.getText(ref, 'my_recipes'),
          onTap: () => _closeAndGo('/my-recipes'),
          ref: ref,
        ),
        _buildSettingsMenuItem(
          svgAsset: 'assets/images/list_alt.svg',
          title: AppTranslations.getText(ref, 'shopping_list'),
          onTap: () => _closeAndGo('/shopping-list'),
          ref: ref,
        ),
        _buildSettingsMenuItem(
          icon: Icons.chat,
          title: AppTranslations.getText(ref, 'chat'),
          onTap: () => _closeAndGo('/chat'),
          ref: ref,
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
          title: AppTranslations.getText(ref, 'support'),
          onTap: () => _closeAndGo('/support'),
          ref: ref,
        ),
        _buildSettingsMenuItem(
          svgAsset: 'assets/images/article_outline.svg',
          title: AppTranslations.getText(ref, 'terms_and_privacy'),
          onTap: () => _closeAndGo('/terms-privacy'),
          ref: ref,
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
          title: AppTranslations.getText(ref, 'logout'),
          onTap: () async {
            final navigator = Navigator.of(hostContext, rootNavigator: true);
            final router = GoRouter.of(hostContext);
            navigator.pop();
            await ref.read(authProvider.notifier).signOut();
            router.go('/login');
          },
          ref: ref,
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
    WidgetRef? ref,
  }) {
    // Check if we're in English mode
    final isEnglish =
        ref != null &&
        ref.read(settingsProvider).language == AppLanguage.english;

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
                child: Transform(
                  alignment: Alignment.center,
                  transform:
                      svgAsset == 'assets/images/logout.svg' && isEnglish
                          ? (Matrix4.identity()
                            ..scale(-1.0, 1.0)) // Flip logout icon for English
                          : Matrix4.identity(),
                  child: SvgPicture.asset(
                    svgAsset,
                    colorFilter: ColorFilter.mode(
                      AppTheme.lightAccentColor.withValues(alpha: 0.6),
                      BlendMode.srcIn,
                    ),
                    fit: BoxFit.contain,
                  ),
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
                textAlign: isEnglish ? TextAlign.left : TextAlign.right,
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
