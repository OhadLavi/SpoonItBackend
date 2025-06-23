import 'package:flutter/material.dart';
import 'dart:io';
import 'package:recipe_keeper/models/recipe.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/providers/recipe_provider.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:recipe_keeper/services/image_service.dart';

class RecipeForm extends ConsumerStatefulWidget {
  final Recipe? initialRecipe;
  final bool isEditing;
  final Function(GlobalKey<FormState>)? onFormReady;
  final VoidCallback? onSubmit;

  const RecipeForm({
    super.key,
    this.initialRecipe,
    this.isEditing = false,
    this.onFormReady,
    this.onSubmit,
  });

  @override
  ConsumerState<RecipeForm> createState() => _RecipeFormState();
}

class _RecipeFormState extends ConsumerState<RecipeForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _prepTimeController;
  late TextEditingController _cookTimeController;
  late TextEditingController _servingsController;
  late TextEditingController _imageUrlController;
  late TextEditingController _notesController;
  late TextEditingController _tagsController;
  late List<TextEditingController> _ingredientControllers;
  late List<TextEditingController> _instructionControllers;
  bool _isLoading = false;
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();
  final ImageService imageService = ImageService();

  @override
  void initState() {
    super.initState();
    _initializeControllers();

    // Pass form key back to parent if needed
    if (widget.onFormReady != null) {
      widget.onFormReady!(_formKey);
    }
  }

  void _initializeControllers() {
    _titleController = TextEditingController(
      text: widget.initialRecipe?.title ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.initialRecipe?.description ?? '',
    );
    _prepTimeController = TextEditingController(
      text: widget.initialRecipe?.prepTime.toString() ?? '',
    );
    _cookTimeController = TextEditingController(
      text: widget.initialRecipe?.cookTime.toString() ?? '',
    );
    _servingsController = TextEditingController(
      text: widget.initialRecipe?.servings.toString() ?? '',
    );
    _imageUrlController = TextEditingController(
      text: widget.initialRecipe?.imageUrl ?? '',
    );
    _notesController = TextEditingController(
      text: widget.initialRecipe?.notes ?? '',
    );
    _tagsController = TextEditingController(
      text: widget.initialRecipe?.tags.join(', ') ?? '',
    );

    _ingredientControllers =
        widget.initialRecipe?.ingredients
            .map((ingredient) => TextEditingController(text: ingredient))
            .toList() ??
        [TextEditingController()];

    _instructionControllers =
        widget.initialRecipe?.instructions
            .map((instruction) => TextEditingController(text: instruction))
            .toList() ??
        [TextEditingController()];
  }

  /// Handles image picking from gallery or camera
  Future<void> _pickImage(ImageSource source, BuildContext context) async {
    try {
      final pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          // Don't clear the image URL when a file is selected
          // We'll use the URL if the file upload isn't implemented
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppTranslations.getText(ref, 'error_selecting_image')}: $e',
          ),
        ),
      );
    }
    Navigator.of(context).pop();
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(AppTranslations.getText(ref, 'select_image_source')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: Text(AppTranslations.getText(ref, 'gallery')),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.gallery, context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: Text(AppTranslations.getText(ref, 'camera')),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.camera, context);
                  },
                ),
                if (_imageFile != null || _imageUrlController.text.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: Text(
                      AppTranslations.getText(ref, 'remove_image'),
                      style: const TextStyle(color: Colors.red),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      setState(() {
                        _imageFile = null;
                        _imageUrlController.clear();
                      });
                    },
                  ),
              ],
            ),
          ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _prepTimeController.dispose();
    _cookTimeController.dispose();
    _servingsController.dispose();
    _imageUrlController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    for (final controller in _ingredientControllers) {
      controller.dispose();
    }
    for (final controller in _instructionControllers) {
      controller.dispose();
    }
    super.dispose();
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

  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Call parent callback if provided
    if (widget.onSubmit != null) {
      widget.onSubmit!();
    }

    // Get the current user from auth state
    final authState = ref.read(authProvider);
    if (authState.status != AuthStatus.authenticated ||
        authState.user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'user_not_authenticated'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Validate required fields
    if (_titleController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppTranslations.getText(ref, 'title_required')),
          ),
        );
      }
      return;
    }

    if (_ingredientControllers.isEmpty ||
        _ingredientControllers.every((c) => c.text.trim().isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'at_least_one_ingredient_required'),
            ),
          ),
        );
      }
      return;
    }

    if (_instructionControllers.isEmpty ||
        _instructionControllers.every((c) => c.text.trim().isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'at_least_one_instruction_required'),
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Handle image URL
    String finalImageUrl = _imageUrlController.text.trim();
    if (_imageFile != null) {
      // If a new file is selected, upload it
      try {
        finalImageUrl = await imageService.uploadRecipeImage(
          _imageFile!,
          authState.user!.uid,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${AppTranslations.getText(ref, 'error_uploading_image')}: $e',
              ),
              backgroundColor: Colors.red, // Added background color
            ),
          );
          setState(() {
            _isLoading = false;
          });
        }
        return; // Stop saving if image upload fails
      }
    } else if (finalImageUrl.isEmpty) {
      // Only use placeholder if NO file selected AND NO URL provided
      finalImageUrl =
          ''; // Default to empty, let Firestore handle default if needed
      // finalImageUrl = "https://via.placeholder.com/400x300?text=No+Image"; // Or keep placeholder
    }

    final recipe = Recipe(
      id: widget.initialRecipe?.id, // Preserve the ID when editing
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      ingredients:
          _ingredientControllers
              .map((controller) => controller.text.trim())
              .where((text) => text.isNotEmpty)
              .toList(),
      instructions:
          _instructionControllers
              .map((controller) => controller.text.trim())
              .where((text) => text.isNotEmpty)
              .toList(),
      prepTime: int.tryParse(_prepTimeController.text) ?? 0,
      cookTime: int.tryParse(_cookTimeController.text) ?? 0,
      servings: int.tryParse(_servingsController.text) ?? 1,
      imageUrl: finalImageUrl, // Use the determined URL
      sourceUrl: widget.initialRecipe?.sourceUrl ?? '',
      userId:
          widget.isEditing ? widget.initialRecipe!.userId : authState.user!.uid,
      createdAt: widget.initialRecipe?.createdAt,
      updatedAt: DateTime.now(),
      tags:
          _tagsController.text
              .split(',')
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty)
              .toList(),
      isFavorite: widget.initialRecipe?.isFavorite ?? false,
      notes: _notesController.text.trim(),
      source: widget.initialRecipe?.source ?? '',
    );

    try {
      if (widget.isEditing) {
        await ref.read(recipeStateProvider.notifier).updateRecipe(recipe);
        ref.refresh(recipeProvider(recipe.id));
      } else {
        await ref.read(recipeStateProvider.notifier).addRecipe(recipe);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEditing
                  ? AppTranslations.getText(ref, 'recipe_updated_successfully')
                  : AppTranslations.getText(ref, 'recipe_saved_successfully'),
            ),
            backgroundColor: Colors.green,
          ),
        );
        if (widget.isEditing) {
          context.go('/recipe/${recipe.id}');
        } else {
          context.go('/home');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppTranslations.getText(ref, 'error_saving_recipe')}: $e',
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

  /// Expose a way to save the recipe from outside this class
  void submitForm() {
    if (!_formKey.currentState!.validate()) {
      // Show a snackbar indicating validation errors
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppTranslations.getText(ref, 'please_fix_errors')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Proceed with saving if validation passes
    _saveRecipe();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<String> tabTitles = [
      AppTranslations.getText(ref, 'basic_information'),
      AppTranslations.getText(ref, 'cooking_details'),
      AppTranslations.getText(ref, 'ingredients'),
      AppTranslations.getText(ref, 'instructions'),
      AppTranslations.getText(ref, 'notes'),
    ];

    return DefaultTabController(
      length: tabTitles.length,
      child: Builder(
        builder: (context) {
          final TabController tabController = DefaultTabController.of(context);

          // Function to validate all tabs and navigate to the first tab with errors
          void validateAllTabs() {
            if (!_formKey.currentState!.validate()) {
              // Check which tab has errors and navigate to it
              if (_titleController.text.isEmpty) {
                // Error in basic info tab
                tabController.animateTo(0);
              } else if (_ingredientControllers.isEmpty ||
                  _ingredientControllers.every((c) => c.text.trim().isEmpty)) {
                // Error in ingredients tab
                tabController.animateTo(2);
              } else if (_instructionControllers.isEmpty ||
                  _instructionControllers.every((c) => c.text.trim().isEmpty)) {
                // Error in instructions tab
                tabController.animateTo(3);
              }
            }
          }

          return Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: validateAllTabs,
            child: Column(
              children: [
                // Tab Bar on top
                Material(
                  color: Theme.of(context).primaryColor,
                  child: TabBar(
                    isScrollable: true,
                    tabs: tabTitles.map((title) => Tab(text: title)).toList(),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    indicatorColor: Colors.white,
                    controller: tabController,
                  ),
                ),

                // Main content area with tabs and navigation arrows
                Expanded(
                  child: Stack(
                    children: [
                      // Tab content
                      Material(
                        child: TabBarView(
                          controller: tabController,
                          children: [
                            // Tab 1: Basic Information
                            _buildBasicInfoTab(context),

                            // Tab 2: Cooking Details
                            _buildCookingDetailsTab(context),

                            // Tab 3: Ingredients
                            _buildIngredientsTab(context),

                            // Tab 4: Instructions
                            _buildInstructionsTab(context),

                            // Tab 5: Notes
                            _buildNotesTab(context),
                          ],
                        ),
                      ),

                      // Left navigation arrow
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: () {
                              if (tabController.index > 0) {
                                tabController.animateTo(
                                  tabController.index - 1,
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).primaryColor.withOpacity(0.6),
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(30),
                                  bottomRight: Radius.circular(30),
                                ),
                              ),
                              child: const Icon(
                                Icons.arrow_back_ios,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Right navigation arrow
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: () {
                              if (tabController.index <
                                  tabController.length - 1) {
                                tabController.animateTo(
                                  tabController.index + 1,
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).primaryColor.withOpacity(0.6),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(30),
                                  bottomLeft: Radius.circular(30),
                                ),
                              ),
                              child: const Icon(
                                Icons.arrow_forward_ios,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Save button at the bottom
                Container(
                  padding: const EdgeInsets.all(16),
                  width: double.infinity,
                  // Use theme-aware color
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed:
                          _isLoading
                              ? null
                              : () {
                                if (_formKey.currentState!.validate()) {
                                  submitForm();
                                }
                              },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        widget.isEditing
                            ? AppTranslations.getText(ref, 'update_recipe')
                            : AppTranslations.getText(ref, 'save_recipe'),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),

                // Loading overlay
                if (_isLoading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.3),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBasicInfoTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: AppTranslations.getText(ref, 'recipe_title'),
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return AppTranslations.getText(ref, 'title_required');
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          // Image upload section
          InkWell(
            onTap: _showImageSourceDialog,
            child: Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color:
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[800]
                        : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).primaryColor.withOpacity(0.5),
                ),
              ),
              child:
                  _imageFile != null
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_imageFile!, fit: BoxFit.cover),
                      )
                      : _imageUrlController.text.isNotEmpty
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: imageService.getCorsProxiedUrl(
                            _imageUrlController.text,
                          ),
                          fit: BoxFit.cover,
                          placeholder:
                              (context, url) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                          errorWidget: (context, url, error) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.image_not_supported,
                                    size: 50,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    AppTranslations.getText(ref, 'image_error'),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      )
                      : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate,
                              size: 50,
                              color: Theme.of(context).primaryColor,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppTranslations.getText(ref, 'add_image'),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
            ),
          ),

          const SizedBox(height: 16),
          // URL input for image
          TextFormField(
            controller: _imageUrlController,
            decoration: InputDecoration(
              labelText: AppTranslations.getText(ref, 'image_url'),
              hintText: AppTranslations.getText(ref, 'enter_image_url'),
              border: const OutlineInputBorder(),
              helperText: AppTranslations.getText(
                ref,
                'image_url_will_be_used',
              ),
            ),
            onChanged: (value) {
              // Trigger UI update when URL changes
              setState(() {});
            },
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: AppTranslations.getText(ref, 'description'),
              hintText: AppTranslations.getText(
                ref,
                'enter_recipe_description',
              ),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor:
                  Theme.of(context).brightness == Brightness.dark
                      ? Colors.black12
                      : Colors.grey[50],
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }

  Widget _buildCookingDetailsTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _prepTimeController,
                  decoration: InputDecoration(
                    labelText: AppTranslations.getText(ref, 'prep_time_mins'),
                    border: const OutlineInputBorder(),
                    suffixText: AppTranslations.getText(ref, 'minutes'),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: TextFormField(
                  controller: _cookTimeController,
                  decoration: InputDecoration(
                    labelText: AppTranslations.getText(ref, 'cook_time_mins'),
                    border: const OutlineInputBorder(),
                    suffixText: AppTranslations.getText(ref, 'minutes'),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _servingsController,
            decoration: InputDecoration(
              labelText: AppTranslations.getText(ref, 'servings'),
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _tagsController,
            decoration: InputDecoration(
              labelText: AppTranslations.getText(ref, 'tags_comma_separated'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientsTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppTranslations.getText(ref, 'ingredients'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: Text(AppTranslations.getText(ref, 'add')),
                onPressed: _addIngredient,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildIngredientsList(),
        ],
      ),
    );
  }

  Widget _buildInstructionsTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppTranslations.getText(ref, 'instructions'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: Text(AppTranslations.getText(ref, 'add')),
                onPressed: _addInstruction,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildInstructionsList(),
        ],
      ),
    );
  }

  Widget _buildNotesTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppTranslations.getText(ref, 'notes'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _notesController,
            decoration: InputDecoration(
              labelText: AppTranslations.getText(ref, 'recipe_notes_optional'),
              border: const OutlineInputBorder(),
            ),
            maxLines: 6,
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientsList() {
    if (_ingredientControllers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Text(
            AppTranslations.getText(ref, 'add_ingredients'),
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _ingredientControllers.length,
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        return Padding(
          key: ValueKey(_ingredientControllers[index]),
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: Icon(Icons.drag_indicator),
                ),
              ),
              Expanded(
                child: TextFormField(
                  controller: _ingredientControllers[index],
                  decoration: InputDecoration(
                    labelText:
                        '${AppTranslations.getText(ref, 'ingredient')} ${index + 1}',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.remove_circle_outline,
                  color: Colors.red,
                  size: 28,
                ),
                padding: const EdgeInsets.all(8.0),
                onPressed: () => _removeIngredient(index),
              ),
            ],
          ),
        );
      },
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) {
            newIndex -= 1;
          }
          final item = _ingredientControllers.removeAt(oldIndex);
          _ingredientControllers.insert(newIndex, item);
        });
      },
    );
  }

  Widget _buildInstructionsList() {
    if (_instructionControllers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Text(
            AppTranslations.getText(ref, 'add_instructions'),
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _instructionControllers.length,
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        return Padding(
          key: ValueKey(_instructionControllers[index]),
          padding: const EdgeInsets.only(bottom: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${AppTranslations.getText(ref, 'step')} ${index + 1}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: Colors.red,
                      size: 28,
                    ),
                    padding: const EdgeInsets.all(8.0),
                    onPressed: () => _removeInstruction(index),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 16.0),
                      child: Icon(Icons.drag_indicator),
                    ),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _instructionControllers[index],
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) {
            newIndex -= 1;
          }
          final item = _instructionControllers.removeAt(oldIndex);
          _instructionControllers.insert(newIndex, item);
        });
      },
    );
  }
}
