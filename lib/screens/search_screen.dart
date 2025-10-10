import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/helpers.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/providers/recipe_provider.dart';
import 'package:recipe_keeper/models/recipe.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:recipe_keeper/services/image_service.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';
  List<Recipe> _searchResults = [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  void _performSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return;
    }

    setState(() {
      _isSearching = true;
      _searchQuery = query;
    });

    final userData = ref.read(userDataProvider).value;
    if (userData != null) {
      ref
          .read(recipeStateProvider.notifier)
          .searchRecipes(userData.id, query)
          .then((_) {
            ref.read(recipeStateProvider).whenData((recipes) {
              setState(() {
                _searchResults = recipes;
                _isSearching = false;
              });
            });
          })
          .catchError((error) {
            setState(() {
              _isSearching = false;
              _searchResults = [];
            });
            if (mounted) {
              Helpers.showSnackBar(
                context,
                AppTranslations.getText(
                  ref,
                  'error_searching_recipes',
                ).replaceAll('{error}', error.toString()),
                isError: true,
              );
            }
          });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _searchResults = [];
    });
    ref.read(recipeStateProvider.notifier).clearSearchResults();
  }

  @override
  Widget build(BuildContext context) {
    final recipesState = ref.watch(recipeStateProvider);

    return Scaffold(
      extendBody: true,
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          AppHeader(title: AppTranslations.getText(ref, 'search')),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: AppTranslations.getText(ref, 'search_recipe'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: AppTheme.backgroundColor,
              ),
              onSubmitted: (_) => _performSearch(),
              textInputAction: TextInputAction.search,
            ),
          ),
          recipesState.when(
            loading:
                () => const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
            error:
                (error, stackTrace) => Expanded(
                  child: Center(
                    child: Text(
                      AppTranslations.getText(
                        ref,
                        'error_searching_recipes',
                      ).replaceAll('{error}', error.toString()),
                    ),
                  ),
                ),
            data: (recipes) {
              if (_isSearching) {
                return const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                    ),
                  ),
                );
              } else if (_searchQuery.isNotEmpty && _searchResults.isEmpty) {
                return Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 80,
                          color: AppTheme.secondaryTextColor.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppTranslations.getText(
                            ref,
                            'no_results_found',
                          ).replaceAll('{query}', _searchQuery),
                          style: const TextStyle(
                            fontFamily: AppTheme.secondaryFontFamily,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppTranslations.getText(ref, 'try_different_search'),
                          style: const TextStyle(
                            fontFamily: AppTheme.secondaryFontFamily,
                            fontSize: 16,
                            color: AppTheme.secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else if (_searchQuery.isEmpty) {
                return Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search,
                          size: 80,
                          color: AppTheme.primaryColor.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppTranslations.getText(ref, 'search_for_recipes'),
                          style: const TextStyle(
                            fontFamily: AppTheme.secondaryFontFamily,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppTranslations.getText(ref, 'find_recipes_by'),
                          style: const TextStyle(
                            fontFamily: AppTheme.secondaryFontFamily,
                            fontSize: 16,
                            color: AppTheme.secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                return Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final recipe = _searchResults[index];
                      return GestureDetector(
                        onTap: () {
                          context.push('/recipe/${recipe.id}');
                        },
                        onLongPress: () {
                          _showRecipeContextMenu(context, recipe);
                        },
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
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
                                        fit: BoxFit.cover,
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
                                      if (recipe.tags.isNotEmpty)
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children:
                                              recipe.tags
                                                  .take(3)
                                                  .map(
                                                    (tag) => Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme
                                                            .primaryColor
                                                            .withValues(
                                                              alpha: 0.1,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        tag,
                                                        style: const TextStyle(
                                                          fontFamily:
                                                              AppTheme
                                                                  .secondaryFontFamily,
                                                          fontSize: 12,
                                                          color:
                                                              AppTheme
                                                                  .primaryColor,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
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
              }
            },
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: -1),
      floatingActionButton:
          _searchQuery.isNotEmpty
              ? FloatingActionButton(
                onPressed: _clearSearch,
                backgroundColor: AppTheme.primaryColor,
                mini: true,
                child: const Icon(Icons.clear),
              )
              : null,
    );
  }
}
