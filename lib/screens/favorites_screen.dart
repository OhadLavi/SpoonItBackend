import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/models/recipe.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/providers/recipe_provider.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/widgets/recipe_card.dart';
import 'package:recipe_keeper/utils/translations.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userDataAsync = ref.watch(userDataProvider);

    return userDataAsync.when(
      data: (userData) {
        if (userData == null || userData.favoriteRecipes.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              title: Text(AppTranslations.getText(ref, 'favorites')),
            ),
            body: _buildEmptyState(context, ref),
          );
        }

        final favoriteRecipesAsync = ref.watch(
          favoriteRecipesProvider(userData.favoriteRecipes),
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(AppTranslations.getText(ref, 'favorites')),
          ),
          body: favoriteRecipesAsync.when(
            data: (recipes) {
              if (recipes.isEmpty) {
                return _buildEmptyState(context, ref);
              }
              return _buildRecipeList(context, recipes);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error:
                (error, stack) => Center(
                  child: Text(
                    AppTranslations.getText(
                      ref,
                      'error_loading_favorites',
                    ).replaceAll('{error}', error.toString()),
                  ),
                ),
          ),
        );
      },
      loading:
          () => Scaffold(
            appBar: AppBar(
              title: Text(AppTranslations.getText(ref, 'favorites')),
            ),
            body: const Center(child: CircularProgressIndicator()),
          ),
      error:
          (error, stack) => Scaffold(
            appBar: AppBar(
              title: Text(AppTranslations.getText(ref, 'favorites')),
            ),
            body: Center(child: Text(error.toString())),
          ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            AppTranslations.getText(ref, 'no_favorites'),
            style: AppTheme.headingStyle,
          ),
          const SizedBox(height: 8),
          Text(
            AppTranslations.getText(ref, 'favorites_description'),
            style: AppTheme.captionStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.go('/home'),
            icon: const Icon(Icons.search),
            label: Text(AppTranslations.getText(ref, 'find_recipes')),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipeList(BuildContext context, List<Recipe> recipes) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 2.5, // Match home grid for less tall cards
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: recipes.length,
        itemBuilder: (context, index) {
          final recipe = recipes[index];
          return RecipeCard(
            recipe: recipe,
            onTap: () => context.go('/recipe/${recipe.id}'),
            isCompact: true,
          );
        },
      ),
    );
  }
}
