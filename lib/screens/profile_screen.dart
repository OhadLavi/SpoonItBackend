import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spoonit/models/app_user.dart';
import 'package:spoonit/providers/auth_provider.dart';
import 'package:spoonit/providers/settings_provider.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/utils/translations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spoonit/services/image_service.dart';
import 'package:spoonit/widgets/app_header.dart';
import 'package:spoonit/widgets/app_bottom_nav.dart';
import 'package:spoonit/widgets/feedback/app_loading_indicator.dart';
import 'package:spoonit/widgets/feedback/app_empty_state.dart';
import 'package:spoonit/services/error_handler_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final userDataAsync = ref.watch(userDataProvider);

    return Scaffold(
      extendBody: true,
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          AppHeader(title: AppTranslations.getText(ref, 'profile')),
          Expanded(
            child: authState.when(
              initial: () => const Center(child: AppLoadingIndicator()),
              loading: () => const Center(child: AppLoadingIndicator()),
              authenticated: (user) {
                return userDataAsync.when(
                  data: (userData) {
                    if (userData == null) {
                      return const AppEmptyState(
                        title: 'User data not found',
                        subtitle: 'Please try logging in again',
                        icon: Icons.person_off,
                        padding: EdgeInsets.only(bottom: 100),
                      );
                    }

                    return _buildProfileContent(context, ref, userData);
                  },
                  loading: () => const Center(child: AppLoadingIndicator()),
                  error: (error, _) => Center(child: Text('Error: $error')),
                );
              },
              unauthenticated: () => _buildSignInPrompt(context, ref),
              error:
                  (errorMessage) => Center(child: Text('Error: $errorMessage')),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: -1),
    );
  }

  Widget _buildSignInPrompt(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.account_circle,
            size: 80,
            color: AppTheme.secondaryTextColor,
          ),
          const SizedBox(height: 16),
          Text(
            AppTranslations.getText(ref, 'not_signed_in'),
            style: AppTheme.headingStyle.copyWith(
              color: AppTheme.textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppTranslations.getText(ref, 'sign_in_prompt'),
            style: AppTheme.captionStyle.copyWith(
              color: AppTheme.textColor.withValues(alpha: 0.7),
            ),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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
                    color: AppTheme.textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  userData.email,
                  style: AppTheme.captionStyle.copyWith(
                    color: AppTheme.textColor.withValues(alpha: 0.7),
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
      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
      backgroundImage:
          photoURL != null && photoURL.isNotEmpty
              ? CachedNetworkImageProvider(
                ImageService().getCorsProxiedUrl(photoURL),
              )
              : null,
      child:
          photoURL == null || photoURL.isEmpty
              ? const Icon(Icons.person, size: 60, color: AppTheme.primaryColor)
              : null,
    );
  }

  Widget _buildStatsSection(
    BuildContext context,
    WidgetRef ref,
    AppUser userData,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppTheme.secondaryTextColor.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppTranslations.getText(ref, 'your_stats'),
              style: AppTheme.subheadingStyle.copyWith(
                color: AppTheme.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  context: context,
                  icon: Icons.restaurant_menu,
                  label: AppTranslations.getText(ref, 'my_recipes'),
                  value: userData.recipeCount.toString(),
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
    return Column(
      children: [
        Icon(icon, color: AppTheme.primaryColor),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTheme.subheadingStyle.copyWith(
            color: AppTheme.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTheme.captionStyle.copyWith(
            color: AppTheme.textColor.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsSection(BuildContext context, WidgetRef ref) {
    final currentLanguage = ref.watch(languageProvider);
    final currentTheme = ref.watch(themeModeProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppTheme.secondaryTextColor.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppTranslations.getText(ref, 'account_settings'),
              style: AppTheme.subheadingStyle.copyWith(
                color: AppTheme.textColor,
                fontWeight: FontWeight.bold,
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
                        content: RadioGroup<AppLanguage>(
                          groupValue: currentLanguage,
                          onChanged: (value) {
                            if (value != null) {
                              ref
                                  .read(settingsProvider.notifier)
                                  .toggleLanguage();
                              Navigator.pop(context);
                            }
                          },
                          child: Column(
                            children: [
                              RadioListTile<AppLanguage>(
                                title: Text(
                                  AppTranslations.getText(ref, 'hebrew'),
                                ),
                                value: AppLanguage.hebrew,
                              ),
                              RadioListTile<AppLanguage>(
                                title: Text(
                                  AppTranslations.getText(ref, 'english'),
                                ),
                                value: AppLanguage.english,
                              ),
                            ],
                          ),
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
                        content: RadioGroup<ThemeMode>(
                          groupValue: currentTheme,
                          onChanged: (value) {
                            if (value != null) {
                              ref
                                  .read(settingsProvider.notifier)
                                  .setThemeMode(value);
                              Navigator.pop(context);
                            }
                          },
                          child: Column(
                            children: [
                              RadioListTile<ThemeMode>(
                                title: Text(
                                  AppTranslations.getText(ref, 'system_theme'),
                                ),
                                value: ThemeMode.system,
                              ),
                              RadioListTile<ThemeMode>(
                                title: Text(
                                  AppTranslations.getText(ref, 'light_theme'),
                                ),
                                value: ThemeMode.light,
                              ),
                              RadioListTile<ThemeMode>(
                                title: Text(
                                  AppTranslations.getText(ref, 'dark_theme'),
                                ),
                                value: ThemeMode.dark,
                              ),
                            ],
                          ),
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
        color: isDestructive ? AppTheme.primaryColor : AppTheme.primaryColor,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? AppTheme.textColor : AppTheme.textColor,
          fontFamily: AppTheme.secondaryFontFamily,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle:
          subtitle != null
              ? Text(
                subtitle,
                style: TextStyle(
                  fontFamily: AppTheme.secondaryFontFamily,
                  fontSize: 12,
                  color: AppTheme.textColor.withValues(alpha: 0.6),
                ),
              )
              : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
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
                  style: const TextStyle(color: AppTheme.errorColor),
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
        builder:
            (context) => const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            ),
      );

      await ref.read(authProvider.notifier).deleteAccount();

      if (context.mounted) Navigator.pop(context);
      if (context.mounted) context.go('/login');
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        final appError = ErrorHandlerService.handleAuthError(e, ref);
        showSnackBar(context, appError.userMessage);
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
        context.go('/home');
      }
    } catch (e) {
      if (context.mounted) {
        final appError = ErrorHandlerService.handleAuthError(e, ref);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appError.userMessage)));
      }
    }
  }
}
