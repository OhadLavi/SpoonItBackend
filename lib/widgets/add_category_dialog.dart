import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/services/category_service.dart';
import 'package:recipe_keeper/models/category.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddCategoryDialog extends ConsumerStatefulWidget {
  const AddCategoryDialog({super.key});

  @override
  ConsumerState<AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends ConsumerState<AddCategoryDialog> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedIcon = 'cake';
  bool _isLoading = false;

  // Predefined icons for categories
  final List<Map<String, dynamic>> _availableIcons = [
    {'name': 'cake', 'icon': Icons.cake, 'label': 'עוגה'},
    {'name': 'room_service', 'icon': Icons.room_service, 'label': 'מנה עיקרית'},
    {'name': 'fastfood', 'icon': Icons.fastfood, 'label': 'מזון מהיר'},
    {'name': 'cookie', 'icon': Icons.cookie, 'label': 'עוגיות'},
    {'name': 'cake_outlined', 'icon': Icons.cake_outlined, 'label': 'עוגות'},
    {'name': 'ramen_dining', 'icon': Icons.ramen_dining, 'label': 'סלטים'},
    {'name': 'bakery_dining', 'icon': Icons.bakery_dining, 'label': 'לחמים'},
    {'name': 'local_pizza', 'icon': Icons.local_pizza, 'label': 'פיצה'},
    {'name': 'restaurant', 'icon': Icons.restaurant, 'label': 'מסעדה'},
    {'name': 'coffee', 'icon': Icons.coffee, 'label': 'קפה'},
    {'name': 'ice_cream', 'icon': Icons.ac_unit, 'label': 'גלידה'},
    {
      'name': 'lunch_dining',
      'icon': Icons.lunch_dining,
      'label': 'ארוחת צהריים',
    },
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'הוסף קטגוריה חדשה',
        style: TextStyle(
          color: Color(0xFF6E3C3F),
          fontFamily: 'Poppins',
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
        textAlign: TextAlign.center,
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Category name field
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8F8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'שם הקטגוריה',
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
              const SizedBox(height: 20),

              // Icon selection
              Text(
                'בחר אייקון',
                style: TextStyle(
                  color: Color(0xFF6E3C3F),
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),

              // Icon grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 1,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _availableIcons.length,
                itemBuilder: (context, index) {
                  final iconData = _availableIcons[index];
                  final isSelected = _selectedIcon == iconData['name'];

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedIcon = iconData['name'];
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? Color(0xFFFF7E6B).withOpacity(0.1)
                                : Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            isSelected
                                ? Border.all(color: Color(0xFFFF7E6B), width: 2)
                                : Border.all(
                                  color: Color(0xFF6E3C3F).withOpacity(0.1),
                                ),
                      ),
                      child: Icon(
                        iconData['icon'],
                        color:
                            isSelected
                                ? Color(0xFFFF7E6B)
                                : Color(0xFF6E3C3F).withOpacity(0.6),
                        size: 24,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: Text(
            'ביטול',
            style: TextStyle(color: Color(0xFF6E3C3F), fontFamily: 'Poppins'),
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _createCategory,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF7E6B),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFFF7E6B).withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child:
              _isLoading
                  ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                  : Text(
                    'הוסף',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
        ),
      ],
    );
  }

  Future<void> _createCategory() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'אנא הכנס שם לקטגוריה',
            style: TextStyle(fontFamily: 'Poppins'),
          ),
          backgroundColor: Color(0xFFFF7E6B),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('משתמש לא מחובר');
      }

      final category = Category(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        icon: _selectedIcon,
        userId: user.uid,
      );

      final categoryService = CategoryService();
      await categoryService.addCategory(category);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'הקטגוריה נוספה בהצלחה!',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: Color(0xFFFF7E6B),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'שגיאה בהוספת הקטגוריה: ${e.toString()}',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
