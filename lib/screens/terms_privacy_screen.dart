import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/translations.dart';

class TermsPrivacyScreen extends ConsumerWidget {
  const TermsPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          AppHeader(title: AppTranslations.getText(ref, 'terms_privacy')),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    title: AppTranslations.getText(ref, 'terms_of_use'),
                    content: AppTranslations.getText(ref, 'terms_content'),
                  ),
                  const SizedBox(height: 24),
                  _buildSection(
                    title: AppTranslations.getText(ref, 'privacy_policy'),
                    content: AppTranslations.getText(ref, 'privacy_content'),
                  ),
                  const SizedBox(height: 24),
                  _buildSection(
                    title: AppTranslations.getText(ref, 'copyright'),
                    content: AppTranslations.getText(ref, 'copyright_content'),
                  ),
                  const SizedBox(height: 24),
                  _buildSection(
                    title: AppTranslations.getText(ref, 'contact'),
                    content: AppTranslations.getText(ref, 'contact_content'),
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: Text(
                      AppTranslations.getText(ref, 'last_updated').replaceAll(
                        '{date}',
                        '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: -1),
    );
  }

  Widget _buildSection({required String title, required String content}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(content, style: const TextStyle(fontSize: 14, height: 1.5)),
      ],
    );
  }
}
