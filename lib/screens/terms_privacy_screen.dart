import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';

class TermsPrivacyScreen extends ConsumerWidget {
  const TermsPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const AppHeader(title: 'תנאים והגנת פרטיות'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    title: 'תנאי שימוש',
                    content: '''
1. השימוש באפליקציה מותנה בקבלת תנאים אלו
2. האפליקציה מיועדת לשימוש אישי בלבד
3. אסור להפיץ תוכן פוגעני או בלתי חוקי
4. אנו שומרים לעצמנו את הזכות לשנות תנאים אלו
5. השימוש באפליקציה על אחריות המשתמש בלבד
              ''',
                  ),
                  const SizedBox(height: 24),
                  _buildSection(
                    title: 'מדיניות פרטיות',
                    content: '''
1. אנו אוספים מידע אישי לצורך מתן השירות
2. המידע נשמר בצורה מאובטחת
3. לא נמכור או נחלוק מידע עם צדדים שלישיים
4. ניתן לבקש מחיקת המידע בכל עת
5. אנו משתמשים בעוגיות לשיפור החוויה
              ''',
                  ),
                  const SizedBox(height: 24),
                  _buildSection(
                    title: 'זכויות יוצרים',
                    content: '''
1. כל התוכן באפליקציה מוגן בזכויות יוצרים
2. אסור להעתיק או להפיץ תוכן ללא רשות
3. המשתמשים שומרים על זכויותיהם לתוכן שהם יוצרים
4. אנו מכבדים זכויות יוצרים של אחרים
              ''',
                  ),
                  const SizedBox(height: 24),
                  _buildSection(
                    title: 'צור קשר',
                    content: '''
לשאלות בנושא תנאי השימוש והפרטיות:
אימייל: privacy@recipekeeper.com
טלפון: +972-50-123-4567
              ''',
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: Text(
                      'עודכן לאחרונה: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const AppBottomNav(currentIndex: -1),
        ],
      ),
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
            color: Color(0xFFFF7E6B),
          ),
        ),
        const SizedBox(height: 8),
        Text(content, style: const TextStyle(fontSize: 14, height: 1.5)),
      ],
    );
  }
}
