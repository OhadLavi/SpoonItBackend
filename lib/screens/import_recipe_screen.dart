import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spoonit/services/recipe_extraction_service.dart';
import 'package:spoonit/services/error_handler_service.dart';
import 'package:spoonit/utils/translations.dart';
import 'package:spoonit/widgets/recipe_form_base.dart';
import 'package:spoonit/widgets/app_header.dart';
import 'package:spoonit/widgets/app_bottom_nav.dart';
import 'package:spoonit/models/recipe.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/widgets/forms/app_text_field.dart';
import 'package:spoonit/widgets/forms/app_form_container.dart';
import 'package:spoonit/widgets/feedback/app_loading_indicator.dart';

class ImportRecipeScreen extends ConsumerStatefulWidget {
  const ImportRecipeScreen({super.key});

  @override
  ConsumerState<ImportRecipeScreen> createState() => _ImportRecipeScreenState();
}

class _ImportRecipeScreenState extends ConsumerState<ImportRecipeScreen> {
  final _urlController = TextEditingController();
  final _recipeExtractionService = RecipeExtractionService();
  bool _isLoading = false;
  AppError? _error;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _importRecipe() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _error = AppError(
          userMessage: AppTranslations.getText(ref, 'url_required'),
          severity: ErrorSeverity.warning,
        );
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
        _error = ErrorHandlerService.handleApiError(e, ref);
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
          AppHeader(title: AppTranslations.getText(ref, 'add_recipe_title')),
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
                      AppFormContainer(
                        child: AppTextField(
                          controller: _urlController,
                          hintText: AppTranslations.getText(ref, 'paste_link'),
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.go,
                          prefixIcon: Icons.link,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          textAlignOverride: TextAlign.right,
                          errorText: _error?.userMessage,
                          onPrefixIconTap: () async {
                            final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
                            if (clipboardData?.text != null && clipboardData!.text!.isNotEmpty) {
                              _urlController.text = clipboardData.text!;
                              setState(() {
                                _error = null;
                              });
                            }
                          },
                          suffixIcon: IconButton(
                            icon: Icon(
                              Icons.send,
                              color: _isLoading
                                  ? AppTheme.textColor.withValues(alpha: 0.5)
                                  : AppTheme.primaryColor,
                            ),
                            onPressed: _isLoading ? null : _importRecipe,
                            iconSize: 20,
                          ),
                          onChanged: (value) {
                            // Clear error when user starts typing
                            if (_error != null) {
                              setState(() {
                                _error = null;
                              });
                            }
                          },
                          onFieldSubmitted: (_) => _importRecipe(),
                        ),
                      ),
                      if (_isLoading) ...[
                        const SizedBox(height: 32),
                        Text(
                          AppTranslations.getText(ref, 'loading_recipe'),
                          style: const TextStyle(
                            color: AppTheme.textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            fontFamily: AppTheme.primaryFontFamily,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const AppLoadingIndicator(),
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
          title: AppTranslations.getText(ref, 'add_recipe_title'),
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
