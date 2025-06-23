import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/services/recipe_extraction_service.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:recipe_keeper/widgets/recipe_form.dart';
import 'package:recipe_keeper/utils/app_theme.dart';

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

      // Navigate to the recipe form with the extracted recipe
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => RecipeForm(initialRecipe: recipe, isEditing: false),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppTranslations.getText(ref, 'import_recipe')),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon and title
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.link_rounded,
                    size: 40,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  AppTranslations.getText(ref, 'paste_recipe_url'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.textColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  AppTranslations.getText(ref, 'import_recipe_description'),
                  style: TextStyle(
                    fontSize: 16,
                    color:
                        isDark ? Colors.white70 : AppTheme.secondaryTextColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // URL input field
                Container(
                  decoration: BoxDecoration(
                    color:
                        isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      if (!isDark)
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
                      hintText: AppTranslations.getText(
                        ref,
                        'enter_recipe_url',
                      ),
                      errorText: _error,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.transparent,
                      prefixIcon: const Icon(
                        Icons.link,
                        color: AppTheme.primaryColor,
                      ),
                      hintStyle: TextStyle(
                        color:
                            isDark
                                ? Colors.white38
                                : AppTheme.secondaryTextColor,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    style: TextStyle(
                      color: isDark ? Colors.white : AppTheme.textColor,
                      fontSize: 16,
                    ),
                    onSubmitted: (_) => _importRecipe(),
                  ),
                ),
                const SizedBox(height: 24),
                // Import button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _importRecipe,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child:
                        _isLoading
                            ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                            : Text(
                              AppTranslations.getText(ref, 'import_recipe'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
