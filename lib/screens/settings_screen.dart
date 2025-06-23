import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/utils/translations.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(AppTranslations.getText(ref, 'settings'))),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(AppTranslations.getText(ref, 'language')),
            subtitle: Text(AppTranslations.getText(ref, 'change_language')),
            onTap: () {
              // TODO: Implement language selection
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: Text(AppTranslations.getText(ref, 'notifications')),
            subtitle: Text(
              AppTranslations.getText(ref, 'manage_notifications'),
            ),
            onTap: () {
              // TODO: Implement notification settings
            },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip),
            title: Text(AppTranslations.getText(ref, 'privacy')),
            subtitle: Text(AppTranslations.getText(ref, 'privacy_settings')),
            onTap: () {
              // TODO: Implement privacy settings
            },
          ),
          ListTile(
            leading: const Icon(Icons.help),
            title: Text(AppTranslations.getText(ref, 'help')),
            subtitle: Text(AppTranslations.getText(ref, 'get_help')),
            onTap: () {
              // TODO: Implement help section
            },
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: Text(AppTranslations.getText(ref, 'about')),
            subtitle: Text(AppTranslations.getText(ref, 'app_info')),
            onTap: () {
              // TODO: Implement about section
            },
          ),
        ],
      ),
    );
  }
}
