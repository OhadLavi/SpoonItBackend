import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spoonit/providers/recipe_provider.dart';
import 'package:spoonit/widgets/recipe_form_base.dart';
import 'package:spoonit/widgets/app_header.dart';
import 'package:spoonit/widgets/app_bottom_nav.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/utils/translations.dart';

class EditRecipeScreen extends ConsumerStatefulWidget {
  final String recipeId;

  const EditRecipeScreen({super.key, required this.recipeId});

  @override
  ConsumerState<EditRecipeScreen> createState() => _EditRecipeScreenState();
}

class _EditRecipeScreenState extends ConsumerState<EditRecipeScreen> {
  @override
  Widget build(BuildContext context) {
    final recipeAsync = ref.watch(recipeProvider(widget.recipeId));

    return recipeAsync.when(
      data: (recipe) {
        if (recipe == null) {
          return Scaffold(
            backgroundColor: AppTheme.backgroundColor,
            body: Column(
              children: [
                AppHeader(
                  title: AppTranslations.getText(ref, 'edit_recipe_title'),
                  showBackButton: true,
                  onBackPressed: () => context.pop(),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.restaurant_menu,
                          size: 80,
                          color: AppTheme.secondaryTextColor.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppTranslations.getText(ref, 'recipe_not_found'),
                          style: const TextStyle(
                            fontFamily: AppTheme.secondaryFontFamily,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: const AppBottomNav(currentIndex: -1),
          );
        }

        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          body: SafeArea(
            child: RecipeFormBase(
              initialRecipe: recipe,
              title: AppTranslations.getText(ref, 'edit_recipe_title'),
              isEditing: true,
              onSuccess: () => context.go('/recipe/${recipe.id}'),
            ),
          ),
          bottomNavigationBar: const AppBottomNav(currentIndex: -1),
        );
      },
      loading:
          () => Scaffold(
            backgroundColor: AppTheme.backgroundColor,
            body: Column(
              children: [
                AppHeader(
                  title: AppTranslations.getText(ref, 'edit_recipe_title'),
                  showBackButton: true,
                  onBackPressed: () => context.pop(),
                ),
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: const AppBottomNav(currentIndex: -1),
          ),
      error:
          (error, stackTrace) => Scaffold(
            backgroundColor: AppTheme.backgroundColor,
            body: Column(
              children: [
                AppHeader(
                  title: AppTranslations.getText(ref, 'edit_recipe_title'),
                  showBackButton: true,
                  onBackPressed: () => context.pop(),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 80,
                          color: AppTheme.secondaryTextColor.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppTranslations.getText(ref, 'error_loading_recipe'),
                          style: const TextStyle(
                            fontFamily: AppTheme.secondaryFontFamily,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error.toString(),
                          style: const TextStyle(
                            fontFamily: AppTheme.secondaryFontFamily,
                            fontSize: 14,
                            color: AppTheme.secondaryTextColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: const AppBottomNav(currentIndex: -1),
          ),
    );
  }
}
