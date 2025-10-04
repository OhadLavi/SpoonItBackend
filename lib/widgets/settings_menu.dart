import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';

class SettingsMenu extends ConsumerWidget {
  const SettingsMenu({super.key, required this.hostContext});
  final BuildContext hostContext;

  void _closeAndGo(String route) {
    // Close the dialog from the root navigator, then navigate using a stable context
    Navigator.of(hostContext, rootNavigator: true).pop();
    GoRouter.of(hostContext).go(route); // use go() for tab-like routes
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _buildSettingsHeader(context, ref),
        const Divider(
          color: Colors.white24,
          height: 1,
        ), // <- remove if you don't want the line
        Expanded(child: _buildSettingsMenu(context, ref)),
      ],
    );
  }

  Widget _buildSettingsHeader(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final name = authState.user?.displayName.trim();
    final email = authState.user?.email.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            (name?.isNotEmpty ?? false) ? name! : 'משתמש',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              fontFamily: 'Heebo',
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            email ?? '',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12.5,
              fontFamily: 'Heebo',
              color: Color(0xFFFF7E6B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsMenu(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        _buildSettingsMenuItem(
          icon: Icons.person_outline,
          title: 'החשבון שלי',
          onTap: () => _closeAndGo('/profile'),
        ),
        _buildSettingsMenuItem(
          icon: Icons.restaurant_menu,
          title: 'המתכונים שלי',
          onTap: () => _closeAndGo('/my-recipes'),
        ),
        _buildSettingsMenuItem(
          icon: Icons.list_alt,
          title: 'רשימת הקניות',
          onTap: () => _closeAndGo('/shopping-list'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Divider(color: Colors.white24, height: 1),
        ),
        _buildSettingsMenuItem(
          icon: Icons.help_outline,
          title: 'תמיכה',
          onTap: () => _closeAndGo('/support'),
        ),
        _buildSettingsMenuItem(
          icon: Icons.article_outlined,
          title: 'תנאים והגנת פרטיות',
          onTap: () => _closeAndGo('/terms-privacy'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Divider(color: Colors.white24, height: 1),
        ),
        _buildSettingsMenuItem(
          icon: Icons.logout,
          title: 'התנתקות',
          onTap: () async {
            Navigator.of(hostContext, rootNavigator: true).pop();
            await ref.read(authProvider.notifier).signOut();
            GoRouter.of(hostContext).go('/login');
          },
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildSettingsMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: Colors.white60, // thinner/lighter
              textDirection: TextDirection.ltr, // prevent RTL mirroring
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70, // thinner/lighter
                  fontWeight: FontWeight.w400,
                  fontFamily: 'Heebo',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
