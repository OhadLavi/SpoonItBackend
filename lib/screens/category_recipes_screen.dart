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

class CategoryRecipesScreen extends ConsumerStatefulWidget {
  final String categoryName;

  const CategoryRecipesScreen({super.key, required this.categoryName});

  @override
  ConsumerState<CategoryRecipesScreen> createState() =>
      _CategoryRecipesScreenState();
}

class _CategoryRecipesScreenState extends ConsumerState<CategoryRecipesScreen> {
  List<Recipe> _getFilteredRecipes(List<Recipe> allRecipes) {
    return allRecipes.where((recipe) {
      return recipe.tags.any(
        (tag) => tag.toLowerCase() == widget.categoryName.toLowerCase(),
      );
    }).toList();
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
      backgroundColor: Colors.white,
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
                    child: CircularProgressIndicator(color: Color(0xFFFF7E6B)),
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
                          'שגיאה בטעינת המתכונים',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
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
                          'אין מתכונים בקטגוריה זו',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'הוסף מתכונים עם התווית "${widget.categoryName}"',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
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
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredRecipes.length,
                    itemBuilder: (context, index) {
                      final recipe = filteredRecipes[index];
                      return GestureDetector(
                        onTap: () {
                          context.push('/recipe/${recipe.id}');
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
                                                color: Color(0xFFFF7E6B),
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
                                        style: const TextStyle(
                                          fontFamily: 'Poppins',
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
                                            fontFamily: 'Poppins',
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
                                              '${recipe.prepTime} דק\'',
                                              style: const TextStyle(
                                                fontFamily: 'Poppins',
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
                                              '${recipe.servings} מנות',
                                              style: const TextStyle(
                                                fontFamily: 'Poppins',
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
          const AppBottomNav(currentIndex: -1),
        ],
      ),
    );
  }
}
