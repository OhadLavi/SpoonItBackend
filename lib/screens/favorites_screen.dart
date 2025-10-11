import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spoonit/models/recipe.dart';
import 'package:spoonit/providers/auth_provider.dart';
import 'package:spoonit/providers/recipe_provider.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/utils/translations.dart';
import 'package:spoonit/widgets/app_header.dart';
import 'package:spoonit/widgets/app_bottom_nav.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  static void _showRecipeContextMenu(
    BuildContext context,
    Recipe recipe,
    WidgetRef ref,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            decoration: const BoxDecoration(
              color: AppTheme.backgroundColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryTextColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.edit, color: AppTheme.primaryColor),
                  title: Text(AppTranslations.getText(ref, 'edit_recipe')),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/edit-recipe/${recipe.id}');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: AppTheme.errorColor),
                  title: Text(AppTranslations.getText(ref, 'delete_recipe')),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmation(context, recipe, ref);
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
    );
  }

  static void _showDeleteConfirmation(
    BuildContext context,
    Recipe recipe,
    WidgetRef ref,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(AppTranslations.getText(ref, 'delete_recipe')),
            content: Text(
              AppTranslations.getText(
                ref,
                'delete_recipe_confirmation',
              ).replaceAll('{recipe}', recipe.title),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppTranslations.getText(ref, 'cancel')),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    await ref
                        .read(recipeStateProvider.notifier)
                        .deleteRecipe(recipe.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppTranslations.getText(
                              ref,
                              'recipe_deleted_successfully',
                            ),
                          ),
                          backgroundColor: AppTheme.successColor,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppTranslations.getText(
                              ref,
                              'error_deleting_recipe',
                            ).replaceAll('{error}', e.toString()),
                          ),
                          backgroundColor: AppTheme.errorColor,
                        ),
                      );
                    }
                  }
                },
                child: Text(
                  AppTranslations.getText(ref, 'delete'),
                  style: const TextStyle(color: AppTheme.errorColor),
                ),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userDataAsync = ref.watch(userDataProvider);

    return userDataAsync.when(
      data: (userData) {
        if (userData == null) {
          return Scaffold(
            backgroundColor: AppTheme.backgroundColor,
            body: Column(
              children: [
                AppHeader(title: AppTranslations.getText(ref, 'my_recipes')),
                Expanded(child: _buildEmptyState(context, ref)),
              ],
            ),
            bottomNavigationBar: const AppBottomNav(currentIndex: -1),
          );
        }

        // Use userRecipesProvider to get all user recipes instead of favorites
        final userRecipesAsync = ref.watch(userRecipesProvider(userData.id));

        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          body: Column(
            children: [
              AppHeader(title: AppTranslations.getText(ref, 'my_recipes')),
              Expanded(
                child: userRecipesAsync.when(
                  data: (recipes) {
                    if (recipes.isEmpty) {
                      return _buildEmptyState(context, ref);
                    }
                    return _buildRecipeList(context, recipes, ref);
                  },
                  loading:
                      () => const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryColor,
                        ),
                      ),
                  error:
                      (error, stack) => Center(
                        child: Text(
                          AppTranslations.getText(
                            ref,
                            'error_loading_recipes',
                          ).replaceAll('{error}', error.toString()),
                        ),
                      ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: const AppBottomNav(currentIndex: -1),
        );
      },
      loading:
          () => Scaffold(
            body: Column(
              children: [
                AppHeader(title: AppTranslations.getText(ref, 'my_recipes')),
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
          (error, stack) => Scaffold(
            body: Column(
              children: [
                AppHeader(
                  title: AppTranslations.getText(ref, 'my_recipes'),
                  onProfileTap: () => context.go('/profile'),
                ),
                Expanded(child: Center(child: Text(error.toString()))),
              ],
            ),
            bottomNavigationBar: const AppBottomNav(currentIndex: -1),
          ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.restaurant_menu,
            size: 80,
            color: AppTheme.secondaryTextColor,
          ),
          const SizedBox(height: 16),
          Text(
            AppTranslations.getText(ref, 'no_recipes_yet'),
            style: AppTheme.headingStyle,
          ),
          const SizedBox(height: 8),
          Text(
            AppTranslations.getText(ref, 'create_first_recipe'),
            style: AppTheme.captionStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.go('/add-recipe'),
            icon: const Icon(Icons.add),
            label: Text(AppTranslations.getText(ref, 'create_new_recipe')),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipeList(
    BuildContext context,
    List<Recipe> recipes,
    WidgetRef ref,
  ) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 100,
        ),
        itemCount: recipes.length,
        itemBuilder: (context, index) {
          final recipe = recipes[index];
          return GestureDetector(
            onTap: () => context.push('/recipe/${recipe.id}'),
            onLongPress: () {
              _showRecipeContextMenu(context, recipe, ref);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.dividerColor.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Recipe image or icon
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child:
                          recipe.imageUrl.isNotEmpty
                              ? ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Image.network(
                                  recipe.imageUrl,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.restaurant_menu,
                                      color: AppTheme.primaryColor,
                                      size: 40,
                                    );
                                  },
                                  loadingBuilder: (
                                    context,
                                    child,
                                    loadingProgress,
                                  ) {
                                    if (loadingProgress == null) return child;
                                    return const Center(
                                      child: CircularProgressIndicator(
                                        color: AppTheme.primaryColor,
                                        strokeWidth: 2,
                                      ),
                                    );
                                  },
                                ),
                              )
                              : const Icon(
                                Icons.restaurant_menu,
                                color: AppTheme.primaryColor,
                                size: 40,
                              ),
                    ),
                  ),

                  // Recipe title in the middle
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        recipe.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textColor,
                          fontFamily: AppTheme.primaryFontFamily,
                        ),
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                  // Arrow pointing right on the right
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundColor.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.arrow_forward,
                        color: AppTheme.textColor,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
