import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/models/recipe.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/providers/recipe_provider.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/widgets/recipe_card.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userDataAsync = ref.watch(userDataProvider);

    return userDataAsync.when(
      data: (userData) {
        if (userData == null) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Column(
              children: [
                const AppHeader(title: 'המתכונים שלי'),
                Expanded(child: _buildEmptyState(context, ref)),
                const AppBottomNav(currentIndex: -1),
              ],
            ),
          );
        }

        // Use userRecipesProvider to get all user recipes instead of favorites
        final userRecipesAsync = ref.watch(userRecipesProvider(userData.id));

        return Scaffold(
          backgroundColor: Colors.white,
          body: Column(
            children: [
              const AppHeader(title: 'המתכונים שלי'),
              Expanded(
                child: userRecipesAsync.when(
                  data: (recipes) {
                    if (recipes.isEmpty) {
                      return _buildEmptyState(context, ref);
                    }
                    return _buildRecipeList(context, recipes);
                  },
                  loading:
                      () => const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFF7E6B),
                        ),
                      ),
                  error:
                      (error, stack) => Center(
                        child: Text(
                          'שגיאה בטעינת המתכונים: ${error.toString()}',
                        ),
                      ),
                ),
              ),
              const AppBottomNav(currentIndex: -1),
            ],
          ),
        );
      },
      loading:
          () => Scaffold(
            body: Column(
              children: [
                const AppHeader(title: 'המתכונים שלי'),
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF7E6B)),
                  ),
                ),
                const AppBottomNav(currentIndex: -1),
              ],
            ),
          ),
      error:
          (error, stack) => Scaffold(
            body: Column(
              children: [
                AppHeader(
                  title: 'המתכונים שלי',
                  onProfileTap: () => context.go('/profile'),
                ),
                Expanded(child: Center(child: Text(error.toString()))),
                const AppBottomNav(currentIndex: -1),
              ],
            ),
          ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.restaurant_menu, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('אין לך מתכונים עדיין', style: AppTheme.headingStyle),
          const SizedBox(height: 8),
          Text(
            'צור את המתכון הראשון שלך',
            style: AppTheme.captionStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.go('/add-recipe'),
            icon: const Icon(Icons.add),
            label: const Text('צור מתכון חדש'),
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
