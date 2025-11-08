import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/providers/auth_provider.dart';
import 'package:spoonit/providers/recipe_provider.dart';
import 'package:spoonit/models/recipe.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spoonit/services/image_service.dart';
import 'package:spoonit/widgets/app_header.dart';
import 'package:spoonit/widgets/app_bottom_nav.dart';
import 'package:spoonit/utils/translations.dart';
import 'package:spoonit/widgets/feedback/app_loading_indicator.dart';
import 'package:spoonit/widgets/feedback/app_empty_state.dart';

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
                  leading: const Icon(Icons.delete, color: AppTheme.errorColor),
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
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  try {
                    await ref
                        .read(recipeStateProvider.notifier)
                        .deleteRecipe(recipe.id);
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(
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
                      scaffoldMessenger.showSnackBar(
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

    // ---- DYNAMIC bottom padding so list never slides under the curved bar ----
    final media = MediaQuery.of(context);
    final double safeBottom = [
      media.padding.bottom,
      media.viewPadding.bottom,
      media.systemGestureInsets.bottom,
    ].reduce(math.max);

    const double kBarHeight = 60.0;
    const double kFabOverlap = 28.0; // matches AppBottomNav
    // Extra breathing room so last card isn't glued to the bar
    const double kListBottomExtra = 24.0;

    final double bottomListPadding =
        kBarHeight + kFabOverlap + safeBottom + kListBottomExtra;

    return Scaffold(
      extendBody: true, // keep: body can draw under the bottom bar
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
              loading: () => const Center(child: AppLoadingIndicator()),
              error:
                  (error, stack) => Center(
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
                          AppTranslations.getText(ref, 'error_loading_recipes'),
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
              data: (allRecipes) {
                final filteredRecipes = _getFilteredRecipes(allRecipes);

                if (filteredRecipes.isEmpty) {
                  return Center(
                    child: AppEmptyState(
                      title: AppTranslations.getText(
                        ref,
                        'no_recipes_in_category',
                      ),
                      subtitle: AppTranslations.getText(
                        ref,
                        'add_recipes_with_tag',
                      ).replaceAll('{tag}', widget.categoryName),
                      icon: Icons.restaurant_menu,
                      padding: const EdgeInsets.only(bottom: 100),
                    ),
                  );
                }

                return ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: ListView.builder(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: bottomListPadding,
                    ),
                    itemCount: filteredRecipes.length,
                    itemBuilder: (context, index) {
                      final recipe = filteredRecipes[index];
                      return GestureDetector(
                        onTap: () => context.push('/recipe/${recipe.id}'),
                        onLongPress:
                            () => _showRecipeContextMenu(context, recipe),
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
                                                .withValues(alpha: 0.1),
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
                                      color: AppTheme.primaryColor.withValues(
                                        alpha: 0.1,
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
                                        style: const TextStyle(
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
                                          style: const TextStyle(
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
                                            const Icon(
                                              Icons.access_time,
                                              size: 14,
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
                                              style: const TextStyle(
                                                fontFamily:
                                                    AppTheme
                                                        .secondaryFontFamily,
                                                fontSize: 11,
                                                color:
                                                    AppTheme.secondaryTextColor,
                                              ),
                                            ),
                                          ],
                                          if (recipe.prepTime > 0 &&
                                              recipe.servings > 0)
                                            const SizedBox(width: 12),
                                          if (recipe.servings > 0) ...[
                                            const Icon(
                                              Icons.people,
                                              size: 14,
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
                                              style: const TextStyle(
                                                fontFamily:
                                                    AppTheme
                                                        .secondaryFontFamily,
                                                fontSize: 11,
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
