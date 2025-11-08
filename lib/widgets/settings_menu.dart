import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spoonit/providers/auth_provider.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'dart:developer' as developer;
import 'package:spoonit/utils/translations.dart';
import 'package:spoonit/widgets/common/directional_text.dart';
import 'package:spoonit/widgets/common/directional_icon.dart';

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
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
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
    // final isEnglish = !LanguageUtils.isHebrew(ref);

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
      padding: const EdgeInsets.fromLTRB(20, 20, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => _closeAndGo('/profile'),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: DirectionalText(
                (name?.isNotEmpty ?? false)
                    ? name!
                    : AppTranslations.getText(ref, 'user'),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppTheme.primaryFontFamily,
                  color: AppTheme.lightAccentColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          DirectionalText(
            email ?? '',
            style: const TextStyle(
              fontSize: 15,
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
      padding: const EdgeInsets.only(top: 0, bottom: 16),
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
          padding: const EdgeInsets.fromLTRB(20, 8, 28, 8),
          child: Divider(
            color: AppTheme.lightAccentColor.withValues(alpha: 0.24),
            thickness: 0.5,
            height: 2,
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
          padding: const EdgeInsets.fromLTRB(20, 8, 28, 8),
          child: Divider(
            color: AppTheme.lightAccentColor.withValues(alpha: 0.24),
            thickness: 0.5,
            height: 2,
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
    // final isEnglish = ref != null && !LanguageUtils.isHebrew(ref);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 28, 16),
        child: Row(
          children: [
            if (svgAsset != null)
              SizedBox(
                width: 20,
                height: 20,
                child: DirectionalIcon.svg(
                  svgAsset,
                  size: 20,
                  color: AppTheme.lightAccentColor.withValues(alpha: 0.6),
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
              child: DirectionalText(
                title,
                style: const TextStyle(
                  fontSize: 17,
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
