import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/providers/recipe_provider.dart';
import 'package:recipe_keeper/models/recipe.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:recipe_keeper/services/image_service.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';
import 'package:recipe_keeper/utils/translations.dart';

class CategoryRecipesScreen extends ConsumerStatefulWidget {
  final String categoryName;
  final String categoryId;

  const CategoryRecipesScreen({
    super.key,
    required this.categoryName,
    required this.categoryId,
  });

  @override
  ConsumerState<CategoryRecipesScreen> createState() =>
      _CategoryRecipesScreenState();
}

class _CategoryRecipesScreenState extends ConsumerState<CategoryRecipesScreen> {
  List<Recipe> _getFilteredRecipes(List<Recipe> allRecipes) {
    return allRecipes.where((recipe) {
      return recipe.categoryId == widget.categoryId;
    }).toList();
  }

  void _showRecipeContextMenu(BuildContext context, Recipe recipe) {
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
                  leading: Icon(Icons.delete, color: AppTheme.errorColor),
                  title: Text(AppTranslations.getText(ref, 'delete_recipe')),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmation(context, recipe);
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Recipe recipe) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(AppTranslations.getText(ref, 'delete_recipe')),
            content: Text(
              AppTranslations.getText(
                ref,
                'delete_recipe_confirmation_with_name',
              ).replaceAll('{recipeName}', recipe.title),
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
                    if (mounted) {
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
                    if (mounted) {
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
                  style: TextStyle(color: AppTheme.errorColor),
                ),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userData = ref.watch(userDataProvider);

    // Use userRecipesProvider which will automatically fetch recipes
    final recipesAsync = userData.when(
      data: (user) {
        if (user == null) {
          return const AsyncValue<List<Recipe>>.data([]);
        }
        return ref.watch(userRecipesProvider(user.id));
      },
      loading: () => const AsyncValue<List<Recipe>>.loading(),
      error: (error, stack) => AsyncValue<List<Recipe>>.error(error, stack),
    );

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          AppHeader(
            title: widget.categoryName,
            showBackButton: true,
            onBackPressed: () => context.pop(),
          ),
          Expanded(
            child: recipesAsync.when(
              loading:
                  () => const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                    ),
                  ),
              error:
                  (error, stack) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 80,
                          color: AppTheme.secondaryTextColor.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppTranslations.getText(ref, 'error_loading_recipes'),
                          style: TextStyle(
                            fontFamily: AppTheme.secondaryFontFamily,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
              data: (allRecipes) {
                final filteredRecipes = _getFilteredRecipes(allRecipes);

                if (filteredRecipes.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.restaurant_menu,
                          size: 80,
                          color: AppTheme.secondaryTextColor.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppTranslations.getText(
                            ref,
                            'no_recipes_in_category',
                          ),
                          style: TextStyle(
                            fontFamily: AppTheme.secondaryFontFamily,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppTranslations.getText(
                            ref,
                            'add_recipes_with_tag',
                          ).replaceAll('{tag}', widget.categoryName),
                          style: TextStyle(
                            fontFamily: AppTheme.secondaryFontFamily,
                            fontSize: 16,
                            color: AppTheme.secondaryTextColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: 100,
                    ),
                    itemCount: filteredRecipes.length,
                    itemBuilder: (context, index) {
                      final recipe = filteredRecipes[index];
                      return GestureDetector(
                        onTap: () {
                          context.push('/recipe/${recipe.id}');
                        },
                        onLongPress: () {
                          _showRecipeContextMenu(context, recipe);
                        },
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          color: AppTheme.cardColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                // Recipe Image
                                if (recipe.imageUrl.isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 80,
                                      height: 80,
                                      child: CachedNetworkImage(
                                        imageUrl: ImageService()
                                            .getCorsProxiedUrl(recipe.imageUrl),
                                        fit: BoxFit.contain,
                                        placeholder:
                                            (context, url) => const Center(
                                              child: CircularProgressIndicator(
                                                color: AppTheme.primaryColor,
                                              ),
                                            ),
                                        errorWidget: (context, url, error) {
                                          return Container(
                                            color: AppTheme.primaryColor
                                                .withOpacity(0.1),
                                            child: const Center(
                                              child: Icon(
                                                Icons
                                                    .image_not_supported_outlined,
                                                color: AppTheme.primaryColor,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor.withOpacity(
                                        0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.restaurant_menu,
                                        color: AppTheme.primaryColor,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 16),

                                // Recipe Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        recipe.title,
                                        style: TextStyle(
                                          fontFamily:
                                              AppTheme.secondaryFontFamily,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textColor,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      if (recipe.description.isNotEmpty)
                                        Text(
                                          recipe.description,
                                          style: TextStyle(
                                            fontFamily:
                                                AppTheme.secondaryFontFamily,
                                            fontSize: 14,
                                            color: AppTheme.secondaryTextColor,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          if (recipe.prepTime > 0) ...[
                                            Icon(
                                              Icons.access_time,
                                              size: 16,
                                              color: AppTheme.primaryColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              AppTranslations.getText(
                                                ref,
                                                'prep_time_short',
                                              ).replaceAll(
                                                '{time}',
                                                recipe.prepTime.toString(),
                                              ),
                                              style: TextStyle(
                                                fontFamily:
                                                    AppTheme
                                                        .secondaryFontFamily,
                                                fontSize: 12,
                                                color:
                                                    AppTheme.secondaryTextColor,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                          ],
                                          if (recipe.servings > 0) ...[
                                            Icon(
                                              Icons.people,
                                              size: 16,
                                              color: AppTheme.primaryColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              AppTranslations.getText(
                                                ref,
                                                'servings_short',
                                              ).replaceAll(
                                                '{count}',
                                                recipe.servings.toString(),
                                              ),
                                              style: TextStyle(
                                                fontFamily:
                                                    AppTheme
                                                        .secondaryFontFamily,
                                                fontSize: 12,
                                                color:
                                                    AppTheme.secondaryTextColor,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: -1),
    );
  }
}
