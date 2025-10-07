import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:developer' as developer;
import 'package:recipe_keeper/models/recipe.dart';
import 'package:recipe_keeper/services/recipe_service.dart';
import 'package:recipe_keeper/services/auth_service.dart';
import 'package:recipe_keeper/providers/auth_provider.dart' as auth;

// State provider for tracking favorite states with immediate UI feedback
class FavoritesUINotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => {};

  void updateFavorite(String recipeId, bool isFavorite) {
    state = {...state, recipeId: isFavorite};
  }

  void removeFavorite(String recipeId) {
    final newState = Map<String, bool>.from(state);
    newState.remove(recipeId);
    state = newState;
  }
}

final favoritesUIProvider =
    NotifierProvider<FavoritesUINotifier, Map<String, bool>>(
      () => FavoritesUINotifier(),
    );

// Define the possible recipe states
enum RecipeStatus { initial, loading, success, error }

// Define the recipe state class
class RecipeState {
  final RecipeStatus status;
  final List<Recipe> recipes;
  final List<Recipe> searchResults;
  final String? errorMessage;

  RecipeState({
    this.status = RecipeStatus.initial,
    this.recipes = const [],
    this.searchResults = const [],
    this.errorMessage,
  });

  // Create a copy of the current state with updated fields
  RecipeState copyWith({
    RecipeStatus? status,
    List<Recipe>? recipes,
    List<Recipe>? searchResults,
    String? errorMessage,
  }) {
    return RecipeState(
      status: status ?? this.status,
      recipes: recipes ?? this.recipes,
      searchResults: searchResults ?? this.searchResults,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// Define the recipe notifier
class RecipeNotifier extends Notifier<AsyncValue<List<Recipe>>> {
  late final RecipeService _recipeService;
  late final AuthService _authService;

  @override
  AsyncValue<List<Recipe>> build() {
    _recipeService = ref.read(recipeServiceProvider);

    // Watch the async auth service provider
    final authServiceAsync = ref.watch(authServiceProvider);

    return authServiceAsync.when(
      data: (authService) {
        _authService = authService;
        return const AsyncValue.loading();
      },
      loading: () => const AsyncValue.loading(),
      error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
    );
  }

  Future<void> loadRecipes() async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        final recipes = await _recipeService.getUserRecipesList(user.uid);
        state = AsyncValue.data(recipes);
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Recipe> importRecipeFromUrl(String url) async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final recipe = await _recipeService.createRecipeFromUrl(url, user.uid);

      // Set the source URL to the imported URL
      final recipeWithSource = recipe.copyWith(sourceUrl: url);

      // Update the state with the new recipe
      state.whenData((recipes) {
        state = AsyncValue.data([recipeWithSource, ...recipes]);
      });

      return recipeWithSource;
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  // Get all recipes for a user
  Future<void> fetchUserRecipes(String userId) async {
    try {
      state = const AsyncValue.loading();

      final recipes = await _recipeService.getUserRecipesList(userId);
      state = AsyncValue.data(recipes);
    } catch (e) {
      developer.log('Error fetching user recipes: $e', name: 'RecipeNotifier');
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  // Get a single recipe by ID
  Future<Recipe?> fetchRecipe(String recipeId) async {
    try {
      final recipe = await _recipeService.getRecipe(recipeId);
      return recipe;
    } catch (e) {
      developer.log('Error fetching recipe: $e', name: 'RecipeNotifier');
      state = AsyncValue.error(e, StackTrace.current);
      return null;
    }
  }

  // Add a new recipe
  Future<void> addRecipe(Recipe recipe) async {
    try {
      state = const AsyncValue.loading();
      developer.log('Adding recipe: ${recipe.id}', name: 'RecipeNotifier');

      // Ensure the recipe has a valid description before saving
      final recipeWithDescription =
          recipe.description.trim().isEmpty
              ? recipe.copyWith(description: '')
              : recipe;

      await _recipeService.addRecipe(recipeWithDescription);

      // Fetch user document first
      final userDoc = await _recipeService.getUserDocument(recipe.userId);
      if (userDoc != null) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final recipes = List<String>.from(userData['recipes'] ?? []);

        if (!recipes.contains(recipe.id)) {
          recipes.add(recipe.id);

          // Update user document with the modified array
          developer.log(
            'Updating user document for recipe add',
            name: 'RecipeNotifier',
          );
          await _recipeService.updateUserDocument(recipe.userId, {
            'recipes': recipes,
            'recipeCount': (userData['recipeCount'] ?? 0) + 1,
            'lastUpdated': Timestamp.fromDate(DateTime.now()),
          });
        }
      }

      // Update the state with the new recipe
      state.whenData((currentRecipes) {
        state = AsyncValue.data([recipeWithDescription, ...currentRecipes]);
      });

      // Invalidate user recipes provider to refresh category views
      ref.invalidate(userRecipesProvider(recipe.userId));
    } catch (e) {
      developer.log('Error adding recipe: $e', name: 'RecipeNotifier');
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  // Delete a recipe
  Future<void> deleteRecipe(String recipeId) async {
    try {
      state = const AsyncValue.loading();
      developer.log('Deleting recipe: $recipeId', name: 'RecipeNotifier');

      // Get the recipe to get the userId
      final recipe = await _recipeService.getRecipe(recipeId);
      if (recipe == null) return;

      // Delete the recipe
      await _recipeService.deleteRecipe(recipeId);

      // Get current user data
      final userDoc = await _recipeService.getUserDocument(recipe.userId);
      if (userDoc != null) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final favoriteRecipes = List<String>.from(
          userData['favoriteRecipes'] ?? [],
        );
        final userRecipes = List<String>.from(userData['recipes'] ?? []);

        // Remove recipe from user's recipes and favorites
        userRecipes.remove(recipeId);
        favoriteRecipes.remove(recipeId);

        // Update user document with modified arrays
        developer.log(
          'Updating user document for recipe delete',
          name: 'RecipeNotifier',
        );
        await _recipeService.updateUserDocument(recipe.userId, {
          'recipes': userRecipes,
          'favoriteRecipes': favoriteRecipes,
          'recipeCount': (userData['recipeCount'] ?? 1) - 1,
          'favoriteCount': favoriteRecipes.length,
          'lastUpdated': Timestamp.fromDate(DateTime.now()),
        });
      }

      // Update the state by removing the deleted recipe
      final currentState = state;
      if (currentState.hasValue) {
        final updatedRecipes =
            currentState.value!.where((r) => r.id != recipeId).toList();
        state = AsyncValue.data(updatedRecipes);
      }

      // Refresh user data and recipe providers
      ref.invalidate(auth.userDataProvider);
      ref.invalidate(userRecipesProvider(recipe.userId));
      ref.invalidate(recipeProvider(recipeId));
      ref.invalidate(recipeStateProvider);
    } catch (e) {
      developer.log('Error deleting recipe: $e', name: 'RecipeNotifier');
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  // Update a recipe
  Future<void> updateRecipe(Recipe recipe) async {
    try {
      state = const AsyncValue.loading();
      developer.log('Updating recipe: ${recipe.id}', name: 'RecipeNotifier');

      // Ensure the recipe has a valid description before saving
      final recipeWithDescription =
          recipe.description.trim().isEmpty
              ? recipe.copyWith(description: '')
              : recipe;

      await _recipeService.updateRecipe(recipeWithDescription);

      // Update the state with the updated recipe
      state.whenData((currentRecipes) {
        final updatedRecipes =
            currentRecipes.map((r) {
              if (r.id == recipe.id) {
                return recipeWithDescription;
              }
              return r;
            }).toList();
        state = AsyncValue.data(updatedRecipes);
      });

      // Refresh recipe providers
      ref.invalidate(recipeProvider(recipe.id));
      ref.invalidate(userRecipesProvider(recipe.userId));
    } catch (e) {
      developer.log('Error updating recipe: $e', name: 'RecipeNotifier');
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  // Optimized toggle favorite method
  Future<void> toggleFavorite(Recipe recipe) async {
    final newFav = !recipe.isFavorite;
    final updated = recipe.copyWith(isFavorite: newFav);

    try {
      // 1. Optimistic UI update
      if (newFav) {
        ref.read(favoritesUIProvider.notifier).updateFavorite(recipe.id, true);
      } else {
        ref.read(favoritesUIProvider.notifier).removeFavorite(recipe.id);
      }

      // 2. Update recipe document
      await _recipeService.updateRecipe(updated);

      // 3. Update user's favorites array
      await _recipeService.updateUserFavorites(
        recipe.userId,
        recipe.id,
        newFav,
      );

      // 4. Update local recipe state
      state.whenData((currentRecipes) {
        final updatedRecipes =
            currentRecipes.map((r) {
              if (r.id == recipe.id) {
                return updated;
              }
              return r;
            }).toList();
        state = AsyncValue.data(updatedRecipes);
      });

      // 5. Clear optimistic state for this recipe
      ref.read(favoritesUIProvider.notifier).removeFavorite(recipe.id);

      // 6. Invalidate only necessary providers
      ref.invalidate(recipeProvider(recipe.id));
      ref.invalidate(auth.userDataProvider);
      ref.invalidate(userRecipesProvider(recipe.userId));
      // Invalidate the main recipe state provider to update all recipe lists
      ref.invalidate(recipeStateProvider);
    } catch (e, st) {
      // 7. Revert optimistic update on error
      ref.read(favoritesUIProvider.notifier).removeFavorite(recipe.id);

      developer.log(
        'Error toggling favorite: $e',
        name: 'RecipeNotifier',
        error: e,
        stackTrace: st,
      );
    }
  }

  // Search recipes
  Future<void> searchRecipes(String userId, String query) async {
    try {
      state = const AsyncValue.loading();

      final allRecipes = await _recipeService.getUserRecipesList(userId);

      // Filter recipes based on the query
      final results =
          allRecipes.where((recipe) {
            final searchText =
                '${recipe.title} ${recipe.description} ${recipe.ingredients.join(' ')} ${recipe.tags.join(' ')}'
                    .toLowerCase();
            return searchText.contains(query.toLowerCase());
          }).toList();

      state = AsyncValue.data(results);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  // Clear search results
  void clearSearchResults() {
    state = const AsyncValue.data([]);
  }
}

// Provider for favorite status
final recipeFavoriteStatusProvider = Provider.family<bool, String>((
  ref,
  recipeId,
) {
  final recipe = ref.watch(recipeProvider(recipeId)).value;
  final optimisticState = ref.watch(favoritesUIProvider)[recipeId];

  // Return optimistic state if available, otherwise fall back to recipe state
  return optimisticState ?? recipe?.isFavorite ?? false;
});

// Provider for Firestore
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

// Provider for the recipe state
final recipeStateProvider =
    NotifierProvider<RecipeNotifier, AsyncValue<List<Recipe>>>(
      () => RecipeNotifier(),
    );

// Provider for a single recipe
final recipeProvider = FutureProvider.family<Recipe?, String>((
  ref,
  recipeId,
) async {
  final recipeService = ref.watch(recipeServiceProvider);
  try {
    final doc = await recipeService.getRecipe(recipeId);
    if (doc != null) {
      return doc;
    }
    return null;
  } catch (e) {
    throw Exception('Failed to fetch recipe: $e');
  }
});

// Provider for user recipes
final userRecipesProvider = FutureProvider.family<List<Recipe>, String>((
  ref,
  userId,
) async {
  final recipeService = ref.watch(recipeServiceProvider);
  try {
    return await recipeService.getUserRecipesList(userId);
  } catch (e) {
    throw Exception('Failed to fetch user recipes: $e');
  }
});

// Provider for favorite recipes
final favoriteRecipesProvider =
    FutureProvider.family<List<Recipe>, List<String>>((ref, favoriteIds) async {
      if (favoriteIds.isEmpty) return [];

      final recipeService = ref.watch(recipeServiceProvider);
      try {
        final List<Recipe> recipes = [];

        // Process favorite IDs in batches of 10
        for (int i = 0; i < favoriteIds.length; i += 10) {
          final end =
              (i + 10 < favoriteIds.length) ? i + 10 : favoriteIds.length;
          final batch = favoriteIds.sublist(i, end);

          final batchRecipes = await recipeService.getRecipesByIds(batch);
          recipes.addAll(batchRecipes);
        }

        return recipes;
      } catch (e) {
        throw Exception('Failed to fetch favorite recipes: $e');
      }
    });

final recipeServiceProvider = Provider<RecipeService>((ref) {
  return RecipeService();
});
