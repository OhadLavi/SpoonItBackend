import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoonit/services/category_service.dart';
import 'package:spoonit/models/category.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/utils/translations.dart';
import 'package:spoonit/services/category_icon_service.dart';

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
  List<Map<String, dynamic>> _availableIcons(WidgetRef ref) => [
    {'name': 'bread', 'label': AppTranslations.getText(ref, 'bread')},
    {'name': 'cookies', 'label': AppTranslations.getText(ref, 'cookies')},
    {'name': 'cakes', 'label': AppTranslations.getText(ref, 'cakes')},
    {'name': 'salads', 'label': AppTranslations.getText(ref, 'salads')},
    {'name': 'sides', 'label': AppTranslations.getText(ref, 'sides')},
    {'name': 'main', 'label': AppTranslations.getText(ref, 'main_dish')},
    {'name': 'pastries', 'label': AppTranslations.getText(ref, 'pastries')},
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
        widget.categoryToEdit != null
            ? AppTranslations.getText(ref, 'edit_category')
            : AppTranslations.getText(ref, 'add_new_category'),
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
                    labelText: AppTranslations.getText(ref, 'category_name'),
                    hintText: AppTranslations.getText(
                      ref,
                      'enter_category_name',
                    ),
                    labelStyle: const TextStyle(
                      color: AppTheme.textColor,
                      fontFamily: AppTheme.secondaryFontFamily,
                    ),
                    hintStyle: TextStyle(
                      color: AppTheme.textColor.withValues(alpha: 0.6),
                      fontFamily: AppTheme.secondaryFontFamily,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppTheme.textColor.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
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
                    color: AppTheme.errorColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.errorColor.withValues(alpha: 0.3),
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

              Text(
                AppTranslations.getText(ref, 'select_icon'),
                style: const TextStyle(
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
                itemCount: _availableIcons(ref).length,
                itemBuilder: (context, index) {
                  final iconData = _availableIcons(ref)[index];
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
                                ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                : AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              isSelected
                                  ? AppTheme.primaryColor
                                  : AppTheme.textColor.withValues(alpha: 0.1),
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
          child: Text(
            AppTranslations.getText(ref, 'cancel'),
            style: const TextStyle(
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
            disabledBackgroundColor: AppTheme.primaryColor.withValues(
              alpha: 0.3,
            ),
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
                    widget.categoryToEdit != null
                        ? AppTranslations.getText(ref, 'update')
                        : AppTranslations.getText(ref, 'add'),
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
        _errorMessage = AppTranslations.getText(
          ref,
          'please_enter_category_name',
        );
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
        throw Exception(AppTranslations.getText(ref, 'user_not_logged_in'));
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
              content: Text(
                AppTranslations.getText(ref, 'category_updated_successfully'),
                style: const TextStyle(
                  fontFamily: AppTheme.secondaryFontFamily,
                ),
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
              content: Text(
                AppTranslations.getText(ref, 'category_added_successfully'),
                style: const TextStyle(
                  fontFamily: AppTheme.secondaryFontFamily,
                ),
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
                  ? AppTranslations.getText(
                    ref,
                    'error_updating_category',
                  ).replaceAll('{error}', e.toString())
                  : AppTranslations.getText(
                    ref,
                    'error_adding_category',
                  ).replaceAll('{error}', e.toString());
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
