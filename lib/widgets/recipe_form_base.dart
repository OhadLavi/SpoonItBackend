import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/models/recipe.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:recipe_keeper/providers/recipe_provider.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/services/validation_service.dart';
import 'package:recipe_keeper/services/category_service.dart';
import 'package:recipe_keeper/models/category.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

/// Base widget for recipe forms that provides common UI and functionality
/// Used by Create, Edit, and Import recipe screens
class RecipeFormBase extends ConsumerStatefulWidget {
  final Recipe? initialRecipe;
  final String title;
  final VoidCallback onSuccess;
  final bool isEditing;

  const RecipeFormBase({
    super.key,
    this.initialRecipe,
    required this.title,
    required this.onSuccess,
    this.isEditing = false,
  });

  @override
  ConsumerState<RecipeFormBase> createState() => _RecipeFormBaseState();
}

class _RecipeFormBaseState extends ConsumerState<RecipeFormBase> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _selectedCategoryId;
  final ImagePicker _imagePicker = ImagePicker();
  File? _selectedImageFile;
  bool _isUploadingImage = false;

  // Form fields
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _prepTimeController;
  late final TextEditingController _cookTimeController;
  late final TextEditingController _servingsController;
  late final TextEditingController _sourceController;
  late final TextEditingController _notesController;
  late final TextEditingController _imageUrlController;

  late final List<TextEditingController> _ingredientControllers;
  late final List<TextEditingController> _instructionControllers;
  late final List<String> _tags;
  final _tagController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // Initialize controllers with initial recipe data if provided
    final recipe = widget.initialRecipe;

    _titleController = TextEditingController(text: recipe?.title ?? '');
    _descriptionController = TextEditingController(
      text: recipe?.description ?? '',
    );
    _prepTimeController = TextEditingController(
      text:
          recipe?.prepTime != null && recipe!.prepTime > 0
              ? recipe.prepTime.toString()
              : '',
    );
    _cookTimeController = TextEditingController(
      text:
          recipe?.cookTime != null && recipe!.cookTime > 0
              ? recipe.cookTime.toString()
              : '',
    );
    _servingsController = TextEditingController(
      text:
          recipe?.servings != null && recipe!.servings > 0
              ? recipe.servings.toString()
              : '',
    );
    _sourceController = TextEditingController(text: recipe?.source ?? '');
    _notesController = TextEditingController(text: recipe?.notes ?? '');
    _imageUrlController = TextEditingController(text: recipe?.imageUrl ?? '');

    // Initialize ingredient controllers
    if (recipe != null && recipe.ingredients.isNotEmpty) {
      _ingredientControllers =
          recipe.ingredients
              .map((ingredient) => TextEditingController(text: ingredient))
              .toList();
    } else {
      _ingredientControllers = List.generate(5, (_) => TextEditingController());
    }

    // Initialize instruction controllers
    if (recipe != null && recipe.instructions.isNotEmpty) {
      _instructionControllers =
          recipe.instructions
              .map((instruction) => TextEditingController(text: instruction))
              .toList();
    } else {
      _instructionControllers = List.generate(
        3,
        (_) => TextEditingController(),
      );
    }

    // Initialize tags
    _tags = recipe?.tags.toList() ?? [];
    _selectedCategoryId = recipe?.categoryId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _prepTimeController.dispose();
    _cookTimeController.dispose();
    _servingsController.dispose();
    _sourceController.dispose();
    _notesController.dispose();
    _imageUrlController.dispose();
    _tagController.dispose();

    for (final controller in _ingredientControllers) {
      controller.dispose();
    }

    for (final controller in _instructionControllers) {
      controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userData = ref.watch(userDataProvider).value;
    final categoriesStream =
        userData != null
            ? CategoryService().getCategories(userData.id)
            : Stream.value(<Category>[]);

    return Container(
      color: AppTheme.backgroundColor,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Image section with "החלף תמונה" overlay
            _buildImageSection(),

            // Content with padding
            Padding(
              padding: const EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Recipe Title
                  _buildTextField(
                    controller: _titleController,
                    label: AppTranslations.getText(ref, 'recipe_title'),
                    hint: AppTranslations.getText(ref, 'enter_recipe_title'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppTranslations.getText(ref, 'title_required');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Category Picker
                  StreamBuilder<List<Category>>(
                    stream: categoriesStream,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SizedBox.shrink();
                      }

                      final categories = snapshot.data!;
                      if (categories.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.cardColor,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.dividerColor.withOpacity(0.5),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                canvasColor: AppTheme.cardColor,
                                cardColor: AppTheme.cardColor,
                                dropdownMenuTheme: DropdownMenuThemeData(
                                  menuStyle: MenuStyle(
                                    backgroundColor: WidgetStateProperty.all(
                                      AppTheme.cardColor,
                                    ),
                                    elevation: WidgetStateProperty.all(10),
                                    shadowColor: WidgetStateProperty.all(
                                      AppTheme.dividerColor.withOpacity(0.5),
                                    ),
                                    shape: WidgetStateProperty.all(
                                      RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              child: DropdownButtonFormField<String>(
                                value: _selectedCategoryId,
                                decoration: InputDecoration(
                                  labelText: 'קטגוריה',
                                  hintText: 'בחר קטגוריה',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: AppTheme.dividerColor,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: AppTheme.dividerColor,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: AppTheme.primaryColor,
                                      width: 2,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: Colors.transparent,
                                  labelStyle: const TextStyle(
                                    color: AppTheme.textColor,
                                    fontFamily: AppTheme.primaryFontFamily,
                                  ),
                                  hintStyle: const TextStyle(
                                    color: AppTheme.textColor,
                                    fontFamily: AppTheme.primaryFontFamily,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                                dropdownColor: AppTheme.cardColor,
                                style: const TextStyle(
                                  color: AppTheme.textColor,
                                  fontFamily: AppTheme.primaryFontFamily,
                                ),
                                selectedItemBuilder: (context) {
                                  return categories.map((category) {
                                    return Container(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        category.name,
                                        style: const TextStyle(
                                          color: AppTheme.textColor,
                                          fontFamily:
                                              AppTheme.primaryFontFamily,
                                        ),
                                      ),
                                    );
                                  }).toList();
                                },
                                isExpanded: true,
                                itemHeight: 56,
                                menuMaxHeight: 320,
                                items:
                                    categories.map((category) {
                                      return DropdownMenuItem<String>(
                                        value: category.id,
                                        child: Directionality(
                                          textDirection: TextDirection.rtl,
                                          child: SizedBox(
                                            width: double.infinity,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 14,
                                                  ),
                                              decoration: const BoxDecoration(
                                                color: AppTheme.cardColor,
                                                border: Border(
                                                  bottom: BorderSide(
                                                    color:
                                                        AppTheme.dividerColor,
                                                    width: 1,
                                                  ),
                                                ),
                                              ),
                                              child: Text(
                                                category.name,
                                                style: const TextStyle(
                                                  color: AppTheme.textColor,
                                                  fontFamily:
                                                      AppTheme
                                                          .primaryFontFamily,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedCategoryId = value;
                                  });
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      );
                    },
                  ),

                  // Cooking Details in separate tiles
                  Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _prepTimeController,
                          label: AppTranslations.getText(ref, 'prep_time_mins'),
                          hint: '0',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _cookTimeController,
                          label: AppTranslations.getText(ref, 'cook_time_mins'),
                          hint: '0',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _servingsController,
                          label: AppTranslations.getText(ref, 'servings'),
                          hint: '1',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Description
                  _buildTextField(
                    controller: _descriptionController,
                    label: AppTranslations.getText(ref, 'description'),
                    hint: AppTranslations.getText(ref, 'enter_description'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),

                  // Ingredients Section
                  _buildSectionTitle(
                    AppTranslations.getText(ref, 'ingredients'),
                  ),
                  _buildReorderableList(_buildIngredientFields(), (
                    oldIndex,
                    newIndex,
                  ) {
                    setState(() {
                      if (newIndex > oldIndex) {
                        newIndex -= 1;
                      }
                      final item = _ingredientControllers.removeAt(oldIndex);
                      _ingredientControllers.insert(newIndex, item);
                    });
                  }),
                  TextButton.icon(
                    onPressed: _addIngredient,
                    icon: const Icon(Icons.add, color: AppTheme.primaryColor),
                    label: Text(
                      AppTranslations.getText(ref, 'add_ingredient'),
                      style: const TextStyle(
                        color: AppTheme.primaryColor,
                        fontFamily: AppTheme.primaryFontFamily,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Instructions Section
                  _buildSectionTitle(
                    AppTranslations.getText(ref, 'instructions'),
                  ),
                  _buildReorderableList(_buildInstructionFields(), (
                    oldIndex,
                    newIndex,
                  ) {
                    setState(() {
                      if (newIndex > oldIndex) {
                        newIndex -= 1;
                      }
                      final item = _instructionControllers.removeAt(oldIndex);
                      _instructionControllers.insert(newIndex, item);
                    });
                  }),
                  TextButton.icon(
                    onPressed: _addInstruction,
                    icon: const Icon(Icons.add, color: AppTheme.primaryColor),
                    label: Text(
                      AppTranslations.getText(ref, 'add_step'),
                      style: const TextStyle(
                        color: AppTheme.primaryColor,
                        fontFamily: AppTheme.primaryFontFamily,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Tags Section
                  _buildSectionTitle(AppTranslations.getText(ref, 'tags')),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _tagController,
                          label: AppTranslations.getText(ref, 'add_tag'),
                          hint: AppTranslations.getText(ref, 'enter_tag'),
                          onSubmitted: (_) => _addTag(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.add,
                          color: AppTheme.primaryColor,
                        ),
                        onPressed: _addTag,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        _tags
                            .map(
                              (tag) => Material(
                                color: Colors.transparent,
                                child: Chip(
                                  label: Text(
                                    tag,
                                    style: const TextStyle(
                                      color: AppTheme.textColor,
                                      fontFamily: AppTheme.primaryFontFamily,
                                    ),
                                  ),
                                  backgroundColor: AppTheme.cardColor,
                                  deleteIconColor: AppTheme.primaryColor,
                                  side: BorderSide.none,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(20),
                                    ),
                                  ),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  onDeleted: () {
                                    setState(() {
                                      _tags.remove(tag);
                                    });
                                  },
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  const SizedBox(height: 24),

                  // Notes Section
                  _buildSectionTitle(AppTranslations.getText(ref, 'notes')),
                  _buildTextField(
                    controller: _notesController,
                    label: AppTranslations.getText(ref, 'recipe_notes'),
                    hint: AppTranslations.getText(ref, 'enter_notes'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveRecipe,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: AppTheme.backgroundColor,
                        disabledBackgroundColor: AppTheme.primaryColor,
                        disabledForegroundColor: AppTheme.backgroundColor,
                        shadowColor: Colors.transparent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        AppTranslations.getText(ref, 'save_recipe'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: AppTheme.primaryFontFamily,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    final imageUrl = _imageUrlController.text;

    return GestureDetector(
      onTap: _showImagePickerOptions,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        child: Container(
          height: 240,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.1),
            image:
                (_selectedImageFile != null)
                    ? DecorationImage(
                      image: FileImage(_selectedImageFile!),
                      fit: BoxFit.cover,
                    )
                    : (imageUrl.isNotEmpty
                        ? DecorationImage(
                          image: CachedNetworkImageProvider(imageUrl),
                          fit: BoxFit.cover,
                        )
                        : null),
          ),
          child: Stack(
            children: [
              // Dark overlay
              Container(color: AppTheme.dividerColor.withOpacity(0.4)),
              // Show loading indicator if uploading
              if (_isUploadingImage)
                const Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.backgroundColor,
                  ),
                )
              else
                // Dashed border container - full size with padding
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: CustomPaint(
                      painter: DashedBorderPainter(
                        color: AppTheme.backgroundColor,
                        strokeWidth: 3,
                        dashWidth: 6,
                        dashSpace: 3,
                      ),
                      child: const Center(
                        child: Text(
                          'החלף תמונה',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.backgroundColor,
                            fontFamily: AppTheme.primaryFontFamily,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppTheme.textColor,
          fontFamily: AppTheme.primaryFontFamily,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int? maxLines,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    void Function(String)? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppTheme.dividerColor.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.dividerColor),
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
            labelStyle: const TextStyle(
              color: AppTheme.textColor,
              fontFamily: AppTheme.primaryFontFamily,
            ),
            hintStyle: const TextStyle(
              color: AppTheme.textColor,
              fontFamily: AppTheme.primaryFontFamily,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          style: const TextStyle(
            color: AppTheme.textColor,
            fontSize: 16,
            fontFamily: AppTheme.primaryFontFamily,
          ),
          textAlign: TextAlign.right,
          maxLines: maxLines ?? 1,
          keyboardType: keyboardType,
          validator: validator,
          onFieldSubmitted: onSubmitted,
        ),
      ),
    );
  }

  List<Widget> _buildIngredientFields() {
    return List.generate(
      _ingredientControllers.length,
      (index) => Container(
        key: ValueKey(_ingredientControllers[index]),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: const Icon(
                    Icons.drag_indicator,
                    color: AppTheme.textColor,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.dividerColor.withOpacity(0.5),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextFormField(
                    controller: _ingredientControllers[index],
                    decoration: InputDecoration(
                      labelText:
                          '${AppTranslations.getText(ref, 'ingredient')} ${index + 1}',
                      hintText: AppTranslations.getText(
                        ref,
                        'enter_ingredient',
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.dividerColor,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.dividerColor,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.primaryColor,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.transparent,
                      labelStyle: const TextStyle(
                        color: AppTheme.textColor,
                        fontFamily: AppTheme.primaryFontFamily,
                      ),
                      hintStyle: const TextStyle(
                        color: AppTheme.textColor,
                        fontFamily: AppTheme.primaryFontFamily,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    style: const TextStyle(
                      color: AppTheme.textColor,
                      fontSize: 16,
                      fontFamily: AppTheme.primaryFontFamily,
                    ),
                  ),
                ),
              ),
              if (index > 0)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => _removeIngredient(index),
                  color: AppTheme.errorColor,
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildInstructionFields() {
    return List.generate(
      _instructionControllers.length,
      (index) => Container(
        key: ValueKey(_instructionControllers[index]),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: const Icon(
                    Icons.drag_indicator,
                    color: AppTheme.textColor,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.dividerColor.withOpacity(0.5),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextFormField(
                    controller: _instructionControllers[index],
                    decoration: InputDecoration(
                      labelText:
                          '${AppTranslations.getText(ref, 'step')} ${index + 1}',
                      hintText: AppTranslations.getText(
                        ref,
                        'enter_instruction',
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.dividerColor,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.dividerColor,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.primaryColor,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.transparent,
                      labelStyle: const TextStyle(
                        color: AppTheme.textColor,
                        fontFamily: AppTheme.primaryFontFamily,
                      ),
                      hintStyle: const TextStyle(
                        color: AppTheme.textColor,
                        fontFamily: AppTheme.primaryFontFamily,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    maxLines: 2,
                    style: const TextStyle(
                      color: AppTheme.textColor,
                      fontSize: 16,
                      fontFamily: AppTheme.primaryFontFamily,
                    ),
                  ),
                ),
              ),
              if (index > 0)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => _removeInstruction(index),
                  color: AppTheme.errorColor,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _addIngredient() {
    setState(() {
      _ingredientControllers.add(TextEditingController());
    });
  }

  void _removeIngredient(int index) {
    setState(() {
      _ingredientControllers[index].dispose();
      _ingredientControllers.removeAt(index);
    });
  }

  void _addInstruction() {
    setState(() {
      _instructionControllers.add(TextEditingController());
    });
  }

  void _removeInstruction(int index) {
    setState(() {
      _instructionControllers[index].dispose();
      _instructionControllers.removeAt(index);
    });
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagController.clear();
      });
    }
  }

  Widget _buildReorderableList(
    List<Widget> items,
    Function(int, int) onReorder,
  ) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: onReorder,
      children: items,
    );
  }

  Future<void> _showImagePickerOptions() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'בחר תמונה',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textColor,
                    fontFamily: AppTheme.primaryFontFamily,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(
                    Icons.camera_alt,
                    color: AppTheme.primaryColor,
                  ),
                  title: const Text(
                    'מצלמה',
                    style: TextStyle(
                      fontFamily: AppTheme.primaryFontFamily,
                      color: AppTheme.textColor,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImageFromCamera();
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library,
                    color: AppTheme.primaryColor,
                  ),
                  title: const Text(
                    'גלריה / בחר קובץ',
                    style: TextStyle(
                      fontFamily: AppTheme.primaryFontFamily,
                      color: AppTheme.textColor,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImageFromGallery();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.link, color: AppTheme.primaryColor),
                  title: const Text(
                    'הוסף קישור',
                    style: TextStyle(
                      fontFamily: AppTheme.primaryFontFamily,
                      color: AppTheme.textColor,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showUrlDialog();
                  },
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImageFile = File(image.path);
        });
        await _uploadImage();
      }
    } catch (e) {
      if (mounted) {
        ValidationService.showErrorSnackBar(
          context,
          'שגיאה בבחירת תמונה: ${e.toString()}',
        );
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImageFile = File(image.path);
        });
        await _uploadImage();
      }
    } catch (e) {
      if (mounted) {
        ValidationService.showErrorSnackBar(
          context,
          'שגיאה בבחירת תמונה: ${e.toString()}',
        );
      }
    }
  }

  Future<void> _showUrlDialog() async {
    final urlController = TextEditingController();

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: AppTheme.backgroundColor,
            title: const Text(
              'הוסף קישור לתמונה',
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                color: AppTheme.textColor,
              ),
            ),
            content: TextField(
              controller: urlController,
              decoration: const InputDecoration(
                hintText: 'הדבק קישור...',
                hintStyle: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  color: AppTheme.textColor,
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: AppTheme.primaryColor,
                    width: 2,
                  ),
                ),
              ),
              style: const TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                color: AppTheme.textColor,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'ביטול',
                  style: TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    color: AppTheme.textColor,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  if (urlController.text.trim().isNotEmpty) {
                    setState(() {
                      _imageUrlController.text = urlController.text.trim();
                      _selectedImageFile = null;
                    });
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  disabledBackgroundColor: AppTheme.primaryColor,
                  disabledForegroundColor: AppTheme.backgroundColor,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                ),
                child: const Text(
                  'אישור',
                  style: TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    color: AppTheme.backgroundColor,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _uploadImage() async {
    if (_selectedImageFile == null) return;

    setState(() {
      _isUploadingImage = true;
    });

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('recipe_images')
          .child(userId)
          .child(fileName);

      await storageRef.putFile(_selectedImageFile!);
      final downloadUrl = await storageRef.getDownloadURL();

      setState(() {
        _imageUrlController.text = downloadUrl;
        _isUploadingImage = false;
      });

      if (mounted) {
        ValidationService.showSuccessSnackBar(context, 'התמונה הועלתה בהצלחה');
      }
    } catch (e) {
      setState(() {
        _isUploadingImage = false;
      });

      if (mounted) {
        ValidationService.showErrorSnackBar(
          context,
          'שגיאה בהעלאת התמונה: ${e.toString()}',
        );
      }
    }
  }

  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Gather ingredients and instructions
    final ingredients =
        _ingredientControllers
            .map((controller) => controller.text.trim())
            .where((text) => text.isNotEmpty)
            .toList();

    final instructions =
        _instructionControllers
            .map((controller) => controller.text.trim())
            .where((text) => text.isNotEmpty)
            .toList();

    // Validate using the validation service
    if (!ValidationService.validateRecipeForm(
      context,
      ref,
      _titleController.text.trim(),
      ingredients,
      instructions,
      categoryId: _selectedCategoryId,
    )) {
      return;
    }

    // Try provider first, then fall back to FirebaseAuth for userId
    final userData = ref.read(userDataProvider).value;
    final fallbackUser = FirebaseAuth.instance.currentUser;
    final userId = userData?.id ?? fallbackUser?.uid;
    if (userId == null) {
      ValidationService.showErrorSnackBar(
        context,
        AppTranslations.getText(ref, 'user_not_authenticated'),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create recipe object
      final recipe = Recipe(
        id: widget.isEditing ? widget.initialRecipe?.id : null,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        ingredients: ingredients,
        instructions: instructions,
        userId: userId,
        imageUrl: _imageUrlController.text.trim(),
        prepTime: int.tryParse(_prepTimeController.text) ?? 0,
        cookTime: int.tryParse(_cookTimeController.text) ?? 0,
        servings: int.tryParse(_servingsController.text) ?? 1,
        tags: _tags,
        source: _sourceController.text.trim(),
        notes: _notesController.text.trim(),
        categoryId: _selectedCategoryId,
      );

      // Save or update recipe
      if (widget.isEditing) {
        await ref.read(recipeStateProvider.notifier).updateRecipe(recipe);
      } else {
        await ref.read(recipeStateProvider.notifier).addRecipe(recipe);
      }

      if (mounted) {
        ValidationService.showSuccessSnackBar(
          context,
          AppTranslations.getText(ref, 'recipe_saved_successfully'),
        );
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        ValidationService.showErrorSnackBar(
          context,
          '${AppTranslations.getText(ref, 'error_saving_recipe')}: ${e.toString()}',
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

// Custom painter for dashed border
class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashSpace,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke;

    final path =
        Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, size.width, size.height),
            const Radius.circular(20),
          ),
        );

    _drawDashedPath(canvas, path, paint);
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final segment = metric.extractPath(distance, distance + dashWidth);
        canvas.drawPath(segment, paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
