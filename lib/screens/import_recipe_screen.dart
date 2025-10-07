import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/services/recipe_extraction_service.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:recipe_keeper/widgets/recipe_form_base.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';
import 'package:recipe_keeper/models/recipe.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          // Header with coral background
          const AppHeader(title: 'הוספת מתכון'),
          // Main content area
          Expanded(
            child: Container(
              color: AppTheme.backgroundColor,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 24.0,
                    right: 24.0,
                    top: 32.0,
                    bottom: 100,
                  ),
                  child: Column(
                    children: [
                      // URL input field at the top
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
                        child: TextField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            hintText: 'הדבק לינק',
                            errorText: _error,
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
                            prefixIcon: GestureDetector(
                              onTap: () async {
                                // Get clipboard data
                                final clipboardData = await Clipboard.getData(
                                  'text/plain',
                                );
                                if (clipboardData?.text != null) {
                                  _urlController.text = clipboardData!.text!;
                                  _importRecipe();
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: SvgPicture.asset(
                                  'assets/images/paste.svg',
                                  width: 24,
                                  height: 24,
                                  colorFilter: const ColorFilter.mode(
                                    AppTheme.uiAccentColor,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
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
                          onSubmitted: (_) => _importRecipe(),
                        ),
                      ),
                      if (_isLoading) ...[
                        const SizedBox(height: 32),
                        // Loading state with cooking pot icon
                        const Text(
                          'טוען מתכון',
                          style: TextStyle(
                            color: AppTheme.textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            fontFamily: AppTheme.primaryFontFamily,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Waiting SVG icon
                        Container(
                          width: 96,
                          height: 96,
                          child: SvgPicture.asset(
                            'assets/images/waiting.svg',
                            width: 96,
                            height: 96,
                            colorFilter: const ColorFilter.mode(
                              AppTheme.primaryColor,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ],
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
        child: RecipeFormBase(
          initialRecipe: widget.recipe,
          title: 'הוספת מתכון',
          isEditing: false,
          onSuccess: () {
            Navigator.pop(context);
            context.go('/my-recipes');
          },
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: -1),
    );
  }
}
