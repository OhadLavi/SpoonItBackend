import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/models/recipe.dart';
import 'package:recipe_keeper/providers/recipe_provider.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:recipe_keeper/utils/app_theme.dart';

class CreateRecipeScreen extends ConsumerStatefulWidget {
  const CreateRecipeScreen({super.key});

  @override
  ConsumerState<CreateRecipeScreen> createState() => _CreateRecipeScreenState();
}

class _CreateRecipeScreenState extends ConsumerState<CreateRecipeScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Form fields
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _prepTimeController = TextEditingController();
  final _cookTimeController = TextEditingController();
  final _servingsController = TextEditingController();
  final _sourceController = TextEditingController();
  final _notesController = TextEditingController();
  final _imageUrlController = TextEditingController();

  final List<TextEditingController> _ingredientControllers = List.generate(
    5,
    (_) => TextEditingController(),
  );
  final List<TextEditingController> _instructionControllers = List.generate(
    3,
    (_) => TextEditingController(),
  );
  final List<String> _tags = [];
  final _tagController = TextEditingController();

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
    return Scaffold(
      appBar: AppBar(
        title: Text(AppTranslations.getText(ref, 'create_recipe')),
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _saveRecipe,
            icon:
                _isLoading
                    ? Container(
                      width: 24,
                      height: 24,
                      padding: const EdgeInsets.all(2.0),
                      child: const CircularProgressIndicator(strokeWidth: 3),
                    )
                    : const Icon(Icons.save),
            label: Text(
              _isLoading
                  ? AppTranslations.getText(ref, 'saving')
                  : AppTranslations.getText(ref, 'save'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Basic Info Section
            _buildSectionTitle(
              AppTranslations.getText(ref, 'basic_information'),
            ),
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
            _buildTextField(
              controller: _descriptionController,
              label: AppTranslations.getText(ref, 'description'),
              hint: AppTranslations.getText(ref, 'enter_description'),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _imageUrlController,
              label: AppTranslations.getText(ref, 'image_url_optional'),
              hint: AppTranslations.getText(ref, 'enter_image_url'),
            ),

            const SizedBox(height: 24),

            // Cooking Details Section
            _buildSectionTitle(AppTranslations.getText(ref, 'cooking_details')),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _prepTimeController,
                    label: AppTranslations.getText(ref, 'prep_time_mins'),
                    hint: '0',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTextField(
                    controller: _cookTimeController,
                    label: AppTranslations.getText(ref, 'cook_time_mins'),
                    hint: '0',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
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

            const SizedBox(height: 24),

            // Ingredients Section
            _buildSectionTitle(AppTranslations.getText(ref, 'ingredients')),
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
              icon: const Icon(Icons.add),
              label: Text(AppTranslations.getText(ref, 'add_ingredient')),
            ),

            const SizedBox(height: 24),

            // Instructions Section
            _buildSectionTitle(AppTranslations.getText(ref, 'instructions')),
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
              icon: const Icon(Icons.add),
              label: Text(AppTranslations.getText(ref, 'add_step')),
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
                IconButton(icon: const Icon(Icons.add), onPressed: _addTag),
              ],
            ),
            Wrap(
              spacing: 8,
              children:
                  _tags
                      .map(
                        (tag) => Chip(
                          label: Text(tag),
                          onDeleted: () {
                            setState(() {
                              _tags.remove(tag);
                            });
                          },
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
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color:
              Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : AppTheme.textColor,
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
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        labelStyle: TextStyle(
          color:
              Theme.of(context).brightness == Brightness.dark
                  ? Colors.white70
                  : AppTheme.textColor,
        ),
        hintStyle: TextStyle(
          color:
              Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[500]
                  : AppTheme.secondaryTextColor,
        ),
      ),
      style: TextStyle(
        color:
            Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : AppTheme.textColor,
      ),
      maxLines: maxLines ?? 1,
      keyboardType: keyboardType,
      validator: validator,
      onFieldSubmitted: onSubmitted,
    );
  }

  List<Widget> _buildIngredientFields() {
    return List.generate(
      _ingredientControllers.length,
      (index) => Padding(
        key: ValueKey(_ingredientControllers[index]),
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Icon(Icons.drag_indicator),
              ),
            ),
            Expanded(
              child: TextFormField(
                controller: _ingredientControllers[index],
                decoration: InputDecoration(
                  labelText:
                      '${AppTranslations.getText(ref, 'ingredient')} ${index + 1}',
                  hintText: AppTranslations.getText(ref, 'enter_ingredient'),
                  border: const OutlineInputBorder(),
                  labelStyle: TextStyle(
                    color:
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.white70
                            : AppTheme.textColor,
                  ),
                  hintStyle: TextStyle(
                    color:
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[500]
                            : AppTheme.secondaryTextColor,
                  ),
                ),
              ),
            ),
            if (index > 0)
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => _removeIngredient(index),
                color: Colors.red,
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildInstructionFields() {
    return List.generate(
      _instructionControllers.length,
      (index) => Padding(
        key: ValueKey(_instructionControllers[index]),
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Icon(Icons.drag_indicator),
              ),
            ),
            Expanded(
              child: TextFormField(
                controller: _instructionControllers[index],
                decoration: InputDecoration(
                  labelText:
                      '${AppTranslations.getText(ref, 'step')} ${index + 1}',
                  hintText: AppTranslations.getText(ref, 'enter_instruction'),
                  border: const OutlineInputBorder(),
                  labelStyle: TextStyle(
                    color:
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.white70
                            : AppTheme.textColor,
                  ),
                  hintStyle: TextStyle(
                    color:
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[500]
                            : AppTheme.secondaryTextColor,
                  ),
                ),
                maxLines: 2,
                style: TextStyle(
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : AppTheme.textColor,
                ),
              ),
            ),
            if (index > 0)
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => _removeInstruction(index),
                color: Colors.red,
              ),
          ],
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
      buildDefaultDragHandles: false,
      onReorder: onReorder,
      children: items,
    );
  }

  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final userData = ref.read(userDataProvider).value;
    if (userData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppTranslations.getText(ref, 'user_not_authenticated')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
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

      // Create recipe object
      final recipe = Recipe(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        ingredients: ingredients,
        instructions: instructions,
        userId: userData.id,
        imageUrl: _imageUrlController.text.trim(),
        prepTime: int.tryParse(_prepTimeController.text) ?? 0,
        cookTime: int.tryParse(_cookTimeController.text) ?? 0,
        servings: int.tryParse(_servingsController.text) ?? 1,
        tags: _tags,
        source: _sourceController.text.trim(),
        notes: _notesController.text.trim(),
      );

      // Save recipe
      await ref.read(recipeStateProvider.notifier).addRecipe(recipe);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'recipe_saved_successfully'),
            ),
            backgroundColor: Colors.lightBlue,
          ),
        );
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppTranslations.getText(ref, 'error_saving_recipe')}: ${e.toString()}',
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
