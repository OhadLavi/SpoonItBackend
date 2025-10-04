import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';

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
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const AppHeader(title: 'תמיכה'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSupportCard(
                  icon: Icons.email,
                  title: 'צור קשר',
                  subtitle: 'שלח לנו אימייל',
                  onTap: () => _showEmailDialog(context),
                ),
                const SizedBox(height: 24),
                const Text(
                  'שאלות נפוצות',
                  style: TextStyle(
                    color: Color(0xFF6E3C3F),
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildFAQItem(
                  question: 'איך מוסיפים מתכון חדש?',
                  answer: 'לחץ על הכפתור + בתחתית המסך ובחר "צור מתכון חדש"',
                ),
                const SizedBox(height: 16),
                _buildFAQItem(
                  question: 'איך שומרים מתכון כמועדף?',
                  answer: 'לחץ על הלב במתכון כדי להוסיף אותו למועדפים',
                ),
                const SizedBox(height: 16),
                _buildFAQItem(
                  question: 'איך מחפשים מתכונים?',
                  answer: 'השתמש בשדה החיפוש בראש המסך הראשי',
                ),
                const SizedBox(height: 16),
                _buildFAQItem(
                  question: 'איך מייבאים מתכון מקישור?',
                  answer: 'לחץ על הכפתור + ובחר "ייבא מקישור"',
                ),
                const SizedBox(height: 16),
                _buildFAQItem(
                  question: 'איך סורקים מתכון מתמונה?',
                  answer: 'לחץ על הכפתור + ובחר "סרוק מתכון"',
                ),
              ],
            ),
          ),
          const AppBottomNav(currentIndex: -1),
        ],
      ),
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
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFFF7E6B)),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF6E3C3F),
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF6E3C3F),
            fontFamily: 'Poppins',
            fontSize: 12,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: Color(0xFF6E3C3F),
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
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: const Text(
                    'צור קשר',
                    style: TextStyle(
                      color: Color(0xFF6E3C3F),
                      fontFamily: 'Poppins',
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
                              'שלח לנו אימייל לתמיכה טכנית',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF6E3C3F).withOpacity(0.8),
                                fontFamily: 'Poppins',
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Title field
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F8F8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: TextField(
                              controller: _titleController,
                              decoration: InputDecoration(
                                labelText: 'כותרת',
                                labelStyle: const TextStyle(
                                  color: Color(0xFF6E3C3F),
                                  fontFamily: 'Poppins',
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Color(0xFF6E3C3F).withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFFF7E6B),
                                    width: 2,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.transparent,
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              style: const TextStyle(
                                color: Color(0xFF6E3C3F),
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Message field
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F8F8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: TextField(
                              controller: _messageController,
                              decoration: InputDecoration(
                                labelText: 'הודעה',
                                labelStyle: const TextStyle(
                                  color: Color(0xFF6E3C3F),
                                  fontFamily: 'Poppins',
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Color(0xFF6E3C3F).withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFFF7E6B),
                                    width: 2,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.transparent,
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              style: const TextStyle(
                                color: Color(0xFF6E3C3F),
                                fontFamily: 'Poppins',
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
                            title: const Text(
                              'אני לא רובוט',
                              style: TextStyle(
                                color: Color(0xFF6E3C3F),
                                fontFamily: 'Poppins',
                                fontSize: 14,
                              ),
                            ),
                            activeColor: const Color(0xFFFF7E6B),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'ביטול',
                        style: TextStyle(
                          color: Color(0xFF6E3C3F),
                          fontFamily: 'Poppins',
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
                        backgroundColor: const Color(0xFFFF7E6B),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(
                          0xFFFF7E6B,
                        ).withOpacity(0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'שלח אימייל',
                        style: TextStyle(
                          fontFamily: 'Poppins',
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

    final String title = _titleController.text.trim();
    final String message = _messageController.text.trim();

    String subject = 'תמיכה טכנית - Recipe Keeper';
    if (title.isNotEmpty) {
      subject = title;
    }

    String body =
        message.isNotEmpty
            ? message
            : 'שלום,\n\nאני זקוק לתמיכה טכנית.\n\nתודה!';

    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@recipekeeper.com',
      query:
          'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('לא ניתן לפתוח אפליקציית אימייל'),
          backgroundColor: Color(0xFFFF7E6B),
        ),
      );
    }
  }

  Widget _buildFAQItem({required String question, required String answer}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
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
                  transform: Matrix4.identity()..scale(-1.0, 1.0),
                  child: const Icon(
                    Icons.help_outline,
                    color: Color(0xFFFF7E6B),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    question,
                    style: const TextStyle(
                      color: Color(0xFF6E3C3F),
                      fontFamily: 'Poppins',
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
                  color: Color(0xFF6E3C3F),
                  fontFamily: 'Poppins',
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
