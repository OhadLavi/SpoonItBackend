import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:spoonit/widgets/app_header.dart';
import 'package:spoonit/widgets/app_bottom_nav.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/utils/translations.dart';

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  bool _isNotRobot = false;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          AppHeader(title: AppTranslations.getText(ref, 'support_title')),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSupportCard(
                  icon: Icons.email,
                  title: AppTranslations.getText(ref, 'contact_us'),
                  subtitle: AppTranslations.getText(ref, 'send_us_email'),
                  onTap: () => _showEmailDialog(context),
                ),
                const SizedBox(height: 24),
                Text(
                  AppTranslations.getText(ref, 'frequently_asked_questions'),
                  style: const TextStyle(
                    color: AppTheme.textColor,
                    fontFamily: AppTheme.secondaryFontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildFAQItem(
                  question: AppTranslations.getText(
                    ref,
                    'how_to_add_new_recipe',
                  ),
                  answer: AppTranslations.getText(
                    ref,
                    'how_to_add_new_recipe_answer',
                  ),
                ),
                const SizedBox(height: 16),
                _buildFAQItem(
                  question: AppTranslations.getText(
                    ref,
                    'how_to_save_favorite',
                  ),
                  answer: AppTranslations.getText(
                    ref,
                    'how_to_save_favorite_answer',
                  ),
                ),
                const SizedBox(height: 16),
                _buildFAQItem(
                  question: AppTranslations.getText(
                    ref,
                    'how_to_search_recipes',
                  ),
                  answer: AppTranslations.getText(
                    ref,
                    'how_to_search_recipes_answer',
                  ),
                ),
                const SizedBox(height: 16),
                _buildFAQItem(
                  question: AppTranslations.getText(
                    ref,
                    'how_to_import_from_url',
                  ),
                  answer: AppTranslations.getText(
                    ref,
                    'how_to_import_from_url_answer',
                  ),
                ),
                const SizedBox(height: 16),
                _buildFAQItem(
                  question: AppTranslations.getText(ref, 'how_to_scan_recipe'),
                  answer: AppTranslations.getText(
                    ref,
                    'how_to_scan_recipe_answer',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: -1),
    );
  }

  Widget _buildSupportCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
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
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primaryColor),
        title: Text(
          title,
          style: const TextStyle(
            color: AppTheme.textColor,
            fontFamily: AppTheme.secondaryFontFamily,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: AppTheme.textColor,
            fontFamily: AppTheme.secondaryFontFamily,
            fontSize: 12,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: AppTheme.textColor,
          size: 16,
        ),
        onTap: onTap,
      ),
    );
  }

  void _showEmailDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  backgroundColor: AppTheme.backgroundColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: Text(
                    AppTranslations.getText(ref, 'contact_us_title'),
                    style: const TextStyle(
                      color: AppTheme.textColor,
                      fontFamily: AppTheme.secondaryFontFamily,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.9,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              AppTranslations.getText(
                                ref,
                                'send_technical_support_email',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppTheme.textColor.withValues(
                                  alpha: 0.8,
                                ),
                                fontFamily: AppTheme.secondaryFontFamily,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Title field
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.cardColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: TextField(
                              controller: _titleController,
                              decoration: InputDecoration(
                                labelText: AppTranslations.getText(
                                  ref,
                                  'title',
                                ),
                                labelStyle: const TextStyle(
                                  color: AppTheme.textColor,
                                  fontFamily: AppTheme.secondaryFontFamily,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: AppTheme.textColor.withValues(
                                      alpha: 0.2,
                                    ),
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: AppTheme.primaryColor,
                                    width: 2,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.transparent,
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              style: const TextStyle(
                                color: AppTheme.textColor,
                                fontFamily: AppTheme.secondaryFontFamily,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Message field
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.cardColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: TextField(
                              controller: _messageController,
                              decoration: InputDecoration(
                                labelText: AppTranslations.getText(
                                  ref,
                                  'message',
                                ),
                                labelStyle: const TextStyle(
                                  color: AppTheme.textColor,
                                  fontFamily: AppTheme.secondaryFontFamily,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: AppTheme.textColor.withValues(
                                      alpha: 0.2,
                                    ),
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: AppTheme.primaryColor,
                                    width: 2,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.transparent,
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              style: const TextStyle(
                                color: AppTheme.textColor,
                                fontFamily: AppTheme.secondaryFontFamily,
                              ),
                              maxLines: 4,
                            ),
                          ),
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            value: _isNotRobot,
                            onChanged: (value) {
                              setState(() {
                                _isNotRobot = value ?? false;
                              });
                            },
                            title: Text(
                              AppTranslations.getText(ref, 'i_am_not_robot'),
                              style: const TextStyle(
                                color: AppTheme.textColor,
                                fontFamily: AppTheme.secondaryFontFamily,
                                fontSize: 14,
                              ),
                            ),
                            activeColor: AppTheme.primaryColor,
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        AppTranslations.getText(ref, 'cancel'),
                        style: const TextStyle(
                          color: AppTheme.textColor,
                          fontFamily: AppTheme.secondaryFontFamily,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed:
                          (_isNotRobot &&
                                  (_titleController.text.trim().isNotEmpty ||
                                      _messageController.text
                                          .trim()
                                          .isNotEmpty))
                              ? () => _launchEmail(context)
                              : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: AppTheme.backgroundColor,
                        disabledBackgroundColor: AppTheme.dividerColor
                            .withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        AppTranslations.getText(ref, 'send_email'),
                        style: const TextStyle(
                          fontFamily: AppTheme.secondaryFontFamily,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
          ),
    );
  }

  void _launchEmail(BuildContext context) async {
    Navigator.pop(context); // Close dialog first
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final String title = _titleController.text.trim();
    final String message = _messageController.text.trim();

    String subject = AppTranslations.getText(ref, 'technical_support_subject');
    if (title.isNotEmpty) {
      subject = title;
    }

    final String body =
        message.isNotEmpty
            ? message
            : AppTranslations.getText(ref, 'default_support_message');

    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@recipekeeper.com',
      query:
          'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'cannot_open_email_app'),
            ),
            backgroundColor: AppTheme.primaryColor,
          ),
        );
      }
    }
  }

  Widget _buildFAQItem({required String question, required String answer}) {
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
            Row(
              children: [
                Transform(
                  alignment: Alignment.center,
                  transform:
                      Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
                  child: const Icon(
                    Icons.help_outline,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    question,
                    style: const TextStyle(
                      color: AppTheme.textColor,
                      fontFamily: AppTheme.secondaryFontFamily,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                answer,
                style: const TextStyle(
                  color: AppTheme.textColor,
                  fontFamily: AppTheme.secondaryFontFamily,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
