import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:recipe_keeper/models/recipe.dart';
import 'package:recipe_keeper/widgets/recipe_form.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/config/env_config.dart';

class ScanRecipeScreen extends ConsumerStatefulWidget {
  const ScanRecipeScreen({super.key});

  @override
  ConsumerState<ScanRecipeScreen> createState() => _ScanRecipeScreenState();
}

class _ScanRecipeScreenState extends ConsumerState<ScanRecipeScreen> {
  bool _isProcessing = false;
  String _statusMessage = '';
  File? _selectedImage;
  Uint8List? _webImage;
  bool get _hasImage => _selectedImage != null || _webImage != null;

  // API endpoint for image processing
  final String apiUrl = '${EnvConfig.apiBaseUrl}/extract_recipe_from_image';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _statusMessage = AppTranslations.getText(ref, 'ready_to_scan');
  }

  Future<void> _pickImageMobile() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _statusMessage = AppTranslations.getText(ref, 'image_selected');
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage =
            '${AppTranslations.getText(ref, 'error')}: ${e.toString()}';
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      // For now we'll just use ImagePicker on mobile platforms
      // This avoids the FilePicker initialization issue
      if (Platform.isAndroid || Platform.isIOS) {
        await _pickImageMobile();
      } else {
        // On web/desktop, show a dialog explaining we need to implement file picking
        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(
                  AppTranslations.getText(ref, 'feature_not_implemented'),
                ),
                content: Text(
                  AppTranslations.getText(ref, 'scan_recipe_description'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(AppTranslations.getText(ref, 'ok')),
                  ),
                ],
              ),
        );
      }
    } catch (e) {
      setState(() {
        _statusMessage =
            '${AppTranslations.getText(ref, 'error')}: ${e.toString()}';
      });
    }
  }

  Future<void> _scanRecipe() async {
    if (!_hasImage) {
      setState(() {
        _statusMessage = AppTranslations.getText(ref, 'please_select_image');
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = AppTranslations.getText(ref, 'scanning_recipe');
    });

    try {
      // For now, implement a mock processing that simulates API call
      // We'll just wait and then show a success message

      // Simulate processing
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      setState(() {
        _statusMessage = AppTranslations.getText(ref, 'processing_text');
      });

      await Future.delayed(const Duration(seconds: 1));

      if (!mounted) return;

      // Create a sample recipe
      final recipe = Recipe(
        title: 'Sample Recipe',
        description: 'This is a placeholder recipe from image scan',
        ingredients: ['Ingredient 1', 'Ingredient 2', 'Ingredient 3'],
        instructions: ['Step 1: Do something', 'Step 2: Do something else'],
        prepTime: 10,
        cookTime: 20,
        servings: 4,
        imageUrl: '',
        sourceUrl: '',
        userId: '',
        tags: ['sample', 'placeholder'],
      );

      // Navigate to the recipe form wrapped in proper screen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => _RecipeFormScreen(recipe: recipe),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage =
              '${AppTranslations.getText(ref, 'error')}: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          const AppHeader(title: 'סריקת מתכון'),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 100),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      // Image preview area
                      InkWell(
                        onTap: _isProcessing ? null : _pickImage,
                        child: Container(
                          width: 300,
                          height: 400,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.primaryColor,
                              width: 2,
                              style: BorderStyle.solid,
                            ),
                          ),
                          child:
                              _hasImage
                                  ? _buildImagePreview()
                                  : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.cloud_upload,
                                        size: 60,
                                        color: AppTheme.secondaryTextColor,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        AppTranslations.getText(
                                          ref,
                                          'drop_image_here',
                                        ),
                                        style: TextStyle(
                                          color: AppTheme.secondaryTextColor,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _statusMessage,
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 16),
                      if (_isProcessing)
                        const CircularProgressIndicator(
                          color: AppTheme.primaryColor,
                        )
                      else if (!_hasImage)
                        ElevatedButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.add_photo_alternate),
                          label: Text(
                            AppTranslations.getText(ref, 'select_image'),
                          ),
                        )
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.refresh),
                              label: Text(
                                AppTranslations.getText(ref, 'change_image'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton.icon(
                              onPressed: _scanRecipe,
                              icon: const Icon(Icons.document_scanner),
                              label: Text(
                                AppTranslations.getText(ref, 'scan_image'),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          AppTranslations.getText(
                            ref,
                            'scan_recipe_instructions',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.secondaryTextColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: -1),
    );
  }

  Widget _buildImagePreview() {
    if (_webImage != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          _webImage!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    } else if (_selectedImage != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          _selectedImage!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }
    return Container();
  }
}

// Wrapper screen for RecipeForm to include header and footer
class _RecipeFormScreen extends ConsumerStatefulWidget {
  final Recipe recipe;

  const _RecipeFormScreen({required this.recipe});

  @override
  ConsumerState<_RecipeFormScreen> createState() => _RecipeFormScreenState();
}

class _RecipeFormScreenState extends ConsumerState<_RecipeFormScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Simple header bar
            Container(
              height: 60,
              decoration: const BoxDecoration(color: AppTheme.primaryColor),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_forward,
                      color: AppTheme.backgroundColor,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      'הוספת מתכון',
                      style: const TextStyle(
                        color: AppTheme.backgroundColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: AppTheme.primaryFontFamily,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48), // Balance the back button
                ],
              ),
            ),
            // Recipe form
            Expanded(
              child: RecipeForm(
                initialRecipe: widget.recipe,
                isEditing: false,
                onSubmit: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'המתכון נשמר בהצלחה!',
                        style: TextStyle(
                          fontFamily: AppTheme.primaryFontFamily,
                          color: AppTheme.backgroundColor,
                        ),
                      ),
                      backgroundColor: AppTheme.primaryColor,
                    ),
                  );
                  Navigator.pop(context);
                  context.go('/my-recipes');
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: -1),
    );
  }
}
