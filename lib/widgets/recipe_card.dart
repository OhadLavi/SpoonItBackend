import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/models/recipe.dart';
import 'package:recipe_keeper/providers/recipe_provider.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/helpers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:recipe_keeper/services/image_service.dart';

class RecipeCard extends ConsumerWidget {
  final Recipe recipe;
  final VoidCallback onTap;
  final bool showFavoriteButton;
  final bool isCompact;

  const RecipeCard({
    super.key,
    required this.recipe,
    required this.onTap,
    this.showFavoriteButton = true,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final favoritesUI = ref.watch(favoritesUIProvider);
    final isFavoriteUI = favoritesUI[recipe.id] ?? recipe.isFavorite;
    final imageService = ImageService();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 140), // Keep card small
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark ? AppTheme.darkCardColor : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              spreadRadius: 1,
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  child: Container(
                    height: isCompact ? 120 : 110, // Make image taller
                    decoration: BoxDecoration(
                      color:
                          recipe.imageUrl.isEmpty
                              ? AppTheme.primaryColor.withOpacity(0.1)
                              : null,
                    ),
                    child:
                        recipe.imageUrl.isNotEmpty
                            ? CachedNetworkImage(
                              imageUrl: imageService.getCorsProxiedUrl(
                                recipe.imageUrl,
                              ),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: isCompact ? 120 : 110,
                              placeholder:
                                  (context, url) => Container(
                                    color: AppTheme.primaryColor.withOpacity(
                                      0.1,
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                              errorWidget: (context, error, stackTrace) {
                                return Container(
                                  color: AppTheme.primaryColor.withOpacity(0.1),
                                  child: const Center(
                                    child: Icon(
                                      Icons.image_not_supported_outlined,
                                      color: AppTheme.primaryColor,
                                      size: 28,
                                    ),
                                  ),
                                );
                              },
                            )
                            : Container(
                              width: double.infinity,
                              height: isCompact ? 120 : 110,
                              color: AppTheme.primaryColor.withOpacity(0.1),
                              child: const Icon(
                                Icons.restaurant_menu,
                                color: AppTheme.primaryColor,
                                size: 32,
                              ),
                            ),
                  ),
                ),
                if (showFavoriteButton)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: GestureDetector(
                      onTap: () {
                        ref
                            .read(favoritesUIProvider.notifier)
                            .update(
                              (state) => {...state, recipe.id: !isFavoriteUI},
                            );
                        final updatedRecipe = recipe.copyWith(
                          isFavorite: !isFavoriteUI,
                        );
                        ref
                            .read(recipeStateProvider.notifier)
                            .toggleFavorite(updatedRecipe);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFavoriteUI ? Icons.favorite : Icons.favorite_border,
                          size: 16,
                          color: isFavoriteUI ? Colors.red : Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Container(
              padding:
                  isCompact
                      ? const EdgeInsets.fromLTRB(6, 0, 6, 0) // Minimal padding
                      : const EdgeInsets.fromLTRB(6, 8, 6, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    recipe.title,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isCompact ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: isCompact ? 14 : 16,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        Helpers.formatCookingTimeWithRef(
                          recipe.prepTime + recipe.cookTime,
                          ref,
                        ),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isCompact ? 13 : 15,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
