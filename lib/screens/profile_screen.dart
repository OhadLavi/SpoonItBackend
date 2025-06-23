import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/models/app_user.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/providers/settings_provider.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:recipe_keeper/services/image_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final userDataAsync = ref.watch(userDataProvider);

    return Scaffold(
      appBar: AppBar(title: Text(AppTranslations.getText(ref, 'profile'))),
      body: authState.when(
        initial: () => const Center(child: CircularProgressIndicator()),
        loading: () => const Center(child: CircularProgressIndicator()),
        authenticated: (user) {
          return userDataAsync.when(
            data: (userData) {
              if (userData == null) {
                return const Center(child: Text('User data not found'));
              }

              return _buildProfileContent(context, ref, userData);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Error: $error')),
          );
        },
        unauthenticated: () => _buildSignInPrompt(context, ref),
        error: (errorMessage) => Center(child: Text('Error: $errorMessage')),
      ),
    );
  }

  Widget _buildSignInPrompt(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_circle, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            AppTranslations.getText(ref, 'not_signed_in'),
            style: AppTheme.headingStyle,
          ),
          const SizedBox(height: 8),
          Text(
            AppTranslations.getText(ref, 'sign_in_prompt'),
            style: AppTheme.captionStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.go('/login'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: Text(AppTranslations.getText(ref, 'sign_in')),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent(
    BuildContext context,
    WidgetRef ref,
    AppUser userData,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile header
          Center(
            child: Column(
              children: [
                _buildProfileImage(userData.photoURL),
                const SizedBox(height: 16),
                Text(
                  userData.displayName,
                  style: AppTheme.headingStyle.copyWith(
                    color: Theme.of(context).textTheme.titleLarge?.color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  userData.email,
                  style: AppTheme.captionStyle.copyWith(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),

          // Stats section
          _buildStatsSection(context, ref, userData),
          const SizedBox(height: 24),

          // Account settings
          _buildSettingsSection(context, ref),
        ],
      ),
    );
  }

  Widget _buildProfileImage(String? photoURL) {
    return CircleAvatar(
      radius: 60,
      backgroundColor: Colors.grey[200],
      backgroundImage:
          photoURL != null && photoURL.isNotEmpty
              ? CachedNetworkImageProvider(
                ImageService().getCorsProxiedUrl(photoURL),
              )
              : null,
      child:
          photoURL == null || photoURL.isEmpty
              ? const Icon(Icons.person, size: 60, color: Colors.grey)
              : null,
    );
  }

  Widget _buildStatsSection(
    BuildContext context,
    WidgetRef ref,
    AppUser userData,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppTranslations.getText(ref, 'your_stats'),
              style: AppTheme.subheadingStyle.copyWith(
                color: Theme.of(context).textTheme.titleLarge?.color,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  context: context,
                  icon: Icons.restaurant_menu,
                  label: AppTranslations.getText(ref, 'recipes'),
                  value: userData.recipeCount.toString(),
                ),
                _buildStatItem(
                  context: context,
                  icon: Icons.favorite,
                  label: AppTranslations.getText(ref, 'favorites'),
                  value: userData.favoriteCount.toString(),
                ),
                _buildStatItem(
                  context: context,
                  icon: Icons.calendar_today,
                  label: AppTranslations.getText(ref, 'member_since'),
                  value: _formatDate(userData.createdAt),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildStatItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color valueColor = isDark ? Colors.white : AppTheme.textColor;
    final Color labelColor =
        isDark ? Colors.white70 : AppTheme.secondaryTextColor;

    return Column(
      children: [
        Icon(icon, color: AppTheme.primaryColor),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTheme.subheadingStyle.copyWith(color: valueColor),
        ),
        const SizedBox(height: 4),
        Text(label, style: AppTheme.captionStyle.copyWith(color: labelColor)),
      ],
    );
  }

  Widget _buildSettingsSection(BuildContext context, WidgetRef ref) {
    final currentLanguage = ref.watch(languageProvider);
    final currentTheme = ref.watch(themeModeProvider);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppTranslations.getText(ref, 'account_settings'),
              style: AppTheme.subheadingStyle.copyWith(
                color: Theme.of(context).textTheme.titleLarge?.color,
              ),
            ),
            const SizedBox(height: 16),
            // Language setting
            _buildSettingItem(
              icon: Icons.language,
              title: AppTranslations.getText(ref, 'language'),
              subtitle:
                  currentLanguage == AppLanguage.hebrew
                      ? AppTranslations.getText(ref, 'hebrew')
                      : AppTranslations.getText(ref, 'english'),
              onTap: () {
                showDialog(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: Text(AppTranslations.getText(ref, 'language')),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RadioListTile<AppLanguage>(
                              title: Text(
                                AppTranslations.getText(ref, 'hebrew'),
                              ),
                              value: AppLanguage.hebrew,
                              groupValue: currentLanguage,
                              onChanged: (value) {
                                if (value != null) {
                                  ref
                                      .read(settingsProvider.notifier)
                                      .toggleLanguage();
                                  Navigator.pop(context);
                                }
                              },
                            ),
                            RadioListTile<AppLanguage>(
                              title: Text(
                                AppTranslations.getText(ref, 'english'),
                              ),
                              value: AppLanguage.english,
                              groupValue: currentLanguage,
                              onChanged: (value) {
                                if (value != null) {
                                  ref
                                      .read(settingsProvider.notifier)
                                      .toggleLanguage();
                                  Navigator.pop(context);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                );
              },
            ),
            const Divider(),
            // Theme setting
            _buildSettingItem(
              icon: Icons.brightness_6,
              title: AppTranslations.getText(ref, 'theme'),
              subtitle: _getThemeText(ref, currentTheme),
              onTap: () {
                showDialog(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: Text(AppTranslations.getText(ref, 'theme')),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RadioListTile<ThemeMode>(
                              title: Text(
                                AppTranslations.getText(ref, 'system_theme'),
                              ),
                              value: ThemeMode.system,
                              groupValue: currentTheme,
                              onChanged: (value) {
                                if (value != null) {
                                  ref
                                      .read(settingsProvider.notifier)
                                      .setThemeMode(value);
                                  Navigator.pop(context);
                                }
                              },
                            ),
                            RadioListTile<ThemeMode>(
                              title: Text(
                                AppTranslations.getText(ref, 'light_theme'),
                              ),
                              value: ThemeMode.light,
                              groupValue: currentTheme,
                              onChanged: (value) {
                                if (value != null) {
                                  ref
                                      .read(settingsProvider.notifier)
                                      .setThemeMode(value);
                                  Navigator.pop(context);
                                }
                              },
                            ),
                            RadioListTile<ThemeMode>(
                              title: Text(
                                AppTranslations.getText(ref, 'dark_theme'),
                              ),
                              value: ThemeMode.dark,
                              groupValue: currentTheme,
                              onChanged: (value) {
                                if (value != null) {
                                  ref
                                      .read(settingsProvider.notifier)
                                      .setThemeMode(value);
                                  Navigator.pop(context);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                );
              },
            ),
            const Divider(),
            // Edit Profile
            _buildSettingItem(
              icon: Icons.person,
              title: AppTranslations.getText(ref, 'edit_profile'),
              onTap: () {
                final userData = ref.read(userDataProvider).value;
                if (userData != null) {
                  context.push('/profile/edit', extra: userData);
                } else {
                  // Handle case where user data is not available (should not happen if authenticated)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppTranslations.getText(ref, 'error_loading_user_data'),
                      ),
                    ),
                  );
                }
              },
            ),
            const Divider(),
            // Delete Account
            _buildSettingItem(
              icon: Icons.delete_forever,
              title: AppTranslations.getText(ref, 'delete_account'),
              onTap: () => _confirmDeleteAccount(context, ref),
              isDestructive: true,
            ),
            const Divider(),
            // Sign Out
            _buildSettingItem(
              icon: Icons.logout,
              title: AppTranslations.getText(ref, 'sign_out'),
              onTap: () => _signOut(context, ref),
              isDestructive: true,
            ),
          ],
        ),
      ),
    );
  }

  String _getThemeText(WidgetRef ref, ThemeMode themeMode) {
    switch (themeMode) {
      case ThemeMode.system:
        return AppTranslations.getText(ref, 'system_theme');
      case ThemeMode.light:
        return AppTranslations.getText(ref, 'light_theme');
      case ThemeMode.dark:
        return AppTranslations.getText(ref, 'dark_theme');
    }
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? Colors.red : AppTheme.primaryColor,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? Colors.red : null,
          fontFamily: 'Poppins',
        ),
      ),
      subtitle:
          subtitle != null
              ? Text(
                subtitle,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
              )
              : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  void _changePassword(BuildContext context, WidgetRef ref) {
    String errorMessage = '';
    final TextEditingController currentController = TextEditingController();
    final TextEditingController newController = TextEditingController();
    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Text(AppTranslations.getText(ref, 'change_password')),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: currentController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: AppTranslations.getText(
                            ref,
                            'current_password',
                          ),
                        ),
                      ),
                      TextField(
                        controller: newController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: AppTranslations.getText(
                            ref,
                            'new_password',
                          ),
                        ),
                      ),
                      if (errorMessage.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            errorMessage,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppTranslations.getText(ref, 'cancel')),
                    ),
                    TextButton(
                      onPressed: () {
                        // Simulated password check; "correctpassword" is the valid current password.
                        if (currentController.text != 'correctpassword') {
                          setState(() {
                            errorMessage = AppTranslations.getText(
                              ref,
                              'wrong_current_password',
                            );
                          });
                        } else {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppTranslations.getText(
                                  ref,
                                  'password_changed',
                                ),
                              ),
                            ),
                          );
                          // TODO: Proceed with actual password update
                        }
                      },
                      child: Text(AppTranslations.getText(ref, 'ok')),
                    ),
                  ],
                ),
          ),
    );
  }

  void _confirmDeleteAccount(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(AppTranslations.getText(ref, 'delete_account')),
            content: Text(
              AppTranslations.getText(ref, 'delete_account_confirmation'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppTranslations.getText(ref, 'cancel')),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteAccount(context, ref);
                },
                child: Text(
                  AppTranslations.getText(ref, 'delete'),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      await ref.read(authProvider.notifier).deleteAccount();

      if (context.mounted) Navigator.pop(context);
      if (context.mounted) context.go('/login');
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        showSnackBar(context, '${AppTranslations.getText(ref, 'error')}: $e');
      }
    }
  }

  void showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authProvider.notifier).signOut();
      if (context.mounted) {
        context.go('/');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error signing out: $e')));
      }
    }
  }
}
