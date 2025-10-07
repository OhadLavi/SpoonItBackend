import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/services/category_service.dart';
import 'package:recipe_keeper/models/category.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/services/category_icon_service.dart';

class AddCategoryDialog extends ConsumerStatefulWidget {
  final Category? categoryToEdit;

  const AddCategoryDialog({super.key, this.categoryToEdit});

  @override
  ConsumerState<AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends ConsumerState<AddCategoryDialog> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedIcon = 'main';
  bool _isLoading = false;
  String? _errorMessage;

  // Available SVG icons for categories - only these 7 icons
  final List<Map<String, dynamic>> _availableIcons = const [
    {'name': 'bread', 'label': 'לחמים'},
    {'name': 'cookies', 'label': 'עוגיות'},
    {'name': 'cakes', 'label': 'עוגות'},
    {'name': 'salads', 'label': 'סלטים'},
    {'name': 'sides', 'label': 'תוספות'},
    {'name': 'main', 'label': 'מנה עיקרית'},
    {'name': 'pastries', 'label': 'מאפים'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.categoryToEdit != null) {
      _nameController.text = widget.categoryToEdit!.name;
      _selectedIcon = widget.categoryToEdit!.icon;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;

    // Let the dialog actually resize on desktop/web
    final horizontalInset =
        screenWidth < 480
            ? 12.0
            : screenWidth < 800
            ? 20.0
            : 32.0;

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: 24,
      ),
      backgroundColor: AppTheme.backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.categoryToEdit != null ? 'ערוך קטגוריה' : 'הוסף קטגוריה חדשה',
        style: const TextStyle(
          color: AppTheme.textColor,
          fontFamily: AppTheme.secondaryFontFamily,
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
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'שם הקטגוריה',
                    hintText: 'הכנס שם לקטגוריה',
                    labelStyle: const TextStyle(
                      color: AppTheme.textColor,
                      fontFamily: AppTheme.secondaryFontFamily,
                    ),
                    hintStyle: TextStyle(
                      color: AppTheme.textColor.withOpacity(0.6),
                      fontFamily: AppTheme.secondaryFontFamily,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppTheme.textColor.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      borderSide: BorderSide(
                        color: AppTheme.primaryColor, // avoid const here
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

              // Error message
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.errorColor.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppTheme.errorColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppTheme.errorColor,
                            fontFamily: AppTheme.secondaryFontFamily,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              const Text(
                'בחר אייקון',
                style: TextStyle(
                  color: AppTheme.textColor,
                  fontFamily: AppTheme.secondaryFontFamily,
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
                  final bool isSelected = _selectedIcon == iconData['name'];

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedIcon = iconData['name'] as String;
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? AppTheme.primaryColor.withOpacity(0.1)
                                : AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              isSelected
                                  ? AppTheme.primaryColor
                                  : AppTheme.textColor.withOpacity(0.1),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: CategoryIconService.getIconByKey(
                            iconData['name'] as String,
                            size: 40,
                          ),
                        ),
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
          child: const Text(
            'ביטול',
            style: TextStyle(
              color: AppTheme.textColor,
              fontFamily: AppTheme.secondaryFontFamily,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _createCategory,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: AppTheme.backgroundColor,
            disabledBackgroundColor: AppTheme.primaryColor.withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child:
              _isLoading
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.backgroundColor,
                      ),
                    ),
                  )
                  : Text(
                    widget.categoryToEdit != null ? 'עדכן' : 'הוסף',
                    style: const TextStyle(
                      fontFamily: AppTheme.secondaryFontFamily,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
        ),
      ],
    );
  }

  Future<void> _createCategory() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'אנא הכנס שם לקטגוריה';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('משתמש לא מחובר');
      }

      final categoryService = CategoryService();

      if (widget.categoryToEdit != null) {
        // Update existing category
        final updatedCategory = Category(
          id: widget.categoryToEdit!.id,
          name: _nameController.text.trim(),
          icon: _selectedIcon,
          userId: user.uid,
        );
        await categoryService.updateCategory(updatedCategory);

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'הקטגוריה עודכנה בהצלחה!',
                style: TextStyle(fontFamily: AppTheme.secondaryFontFamily),
              ),
              backgroundColor: AppTheme.primaryColor,
            ),
          );
        }
      } else {
        // Create new category
        final category = Category(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: _nameController.text.trim(),
          icon: _selectedIcon,
          userId: user.uid,
        );
        await categoryService.addCategory(category);

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'הקטגוריה נוספה בהצלחה!',
                style: TextStyle(fontFamily: AppTheme.secondaryFontFamily),
              ),
              backgroundColor: AppTheme.primaryColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              widget.categoryToEdit != null
                  ? 'שגיאה בעדכון הקטגוריה: ${e.toString()}'
                  : 'שגיאה בהוספת הקטגוריה: ${e.toString()}';
        });
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
