import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/services/recipe_extraction_service.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:recipe_keeper/widgets/recipe_form.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';
import 'package:recipe_keeper/models/recipe.dart';

class ImportRecipeScreen extends ConsumerStatefulWidget {
  const ImportRecipeScreen({super.key});

  @override
  ConsumerState<ImportRecipeScreen> createState() => _ImportRecipeScreenState();
}

class _ImportRecipeScreenState extends ConsumerState<ImportRecipeScreen> {
  final _urlController = TextEditingController();
  final _recipeExtractionService = RecipeExtractionService();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _importRecipe() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _error = AppTranslations.getText(ref, 'url_required');
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final recipe = await _recipeExtractionService.extractRecipeFromUrl(url);
      if (!mounted) return;

      // Navigate to the recipe form with the extracted recipe wrapped in proper screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => _RecipeFormScreen(recipe: recipe),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Header with coral background
          const AppHeader(title: 'הוספת מתכון'),
          // Main content area
          Expanded(
            child: Container(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 32.0,
                ),
                child: Column(
                  children: [
                    // URL input field at the top
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _urlController,
                        decoration: InputDecoration(
                          hintText: 'הדבק לינק',
                          errorText: _error,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.transparent,
                          prefixIcon: GestureDetector(
                            onTap: _importRecipe,
                            child: const Icon(
                              Icons.content_paste,
                              color: Colors.grey,
                            ),
                          ),
                          hintStyle: const TextStyle(color: Colors.grey),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                        ),
                        onSubmitted: (_) => _importRecipe(),
                      ),
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 32),
                      // Loading state with cooking pot icon
                      const Text(
                        'טוען מתכון',
                        style: TextStyle(
                          color: Color(0xFF8B4513), // Dark brown/maroon
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Cooking pot icon
                      Container(
                        width: 60,
                        height: 60,
                        decoration: const BoxDecoration(
                          color: Color(0xFF8B4513),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.restaurant,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // Bottom navigation bar
          const AppBottomNav(currentIndex: -1),
        ],
      ),
    );
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Simple header bar
            Container(
              height: 60,
              decoration: const BoxDecoration(color: Color(0xFFFF7E6B)),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_forward, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      'הוספת מתכון',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Heebo',
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
                          fontFamily: 'Heebo',
                          color: Colors.white,
                        ),
                      ),
                      backgroundColor: Color(0xFFFF7E6B),
                    ),
                  );
                  Navigator.pop(context);
                  context.go('/my-recipes');
                },
              ),
            ),
            // Bottom navigation
            const AppBottomNav(currentIndex: -1),
          ],
        ),
      ),
    );
  }
}
