import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'dart:developer' as developer;
import 'package:html/parser.dart' as html_parser;
import 'package:recipe_keeper/models/recipe.dart';
import 'package:recipe_keeper/services/firebase_service.dart';

class RecipeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Collection reference
  CollectionReference get _recipesCollection =>
      _firestore.collection('recipes');
  CollectionReference get _usersCollection => _firestore.collection('users');

  // Get all recipes for a user
  Stream<List<Recipe>> getUserRecipes(String userId) {
    FirebaseService.logFirestoreOperation('stream', 'recipes', null, {
      'userId': userId,
    });
    return _recipesCollection
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => Recipe.fromFirestore(doc)).toList();
        });
  }

  // Get user recipes once (not as a stream)
  Future<List<Recipe>> getUserRecipesOnce(String userId) async {
    final QuerySnapshot snapshot =
        await _recipesCollection
            .where('userId', isEqualTo: userId)
            .orderBy('createdAt', descending: true)
            .get();

    return snapshot.docs.map((doc) => Recipe.fromFirestore(doc)).toList();
  }

  // Get favorite recipes for a user
  Stream<List<Recipe>> getUserFavoriteRecipes(String userId) {
    return _recipesCollection
        .where('userId', isEqualTo: userId)
        .where('isFavorite', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => Recipe.fromFirestore(doc)).toList();
        });
  }

  // Get recipes by IDs
  Future<List<Recipe>> getRecipesByIds(List<String> recipeIds) async {
    if (recipeIds.isEmpty) return [];

    // Firestore can only handle up to 10 IDs in a where-in query
    // So we need to batch the requests
    final List<Recipe> recipes = [];

    for (int i = 0; i < recipeIds.length; i += 10) {
      final end = (i + 10 < recipeIds.length) ? i + 10 : recipeIds.length;
      final batch = recipeIds.sublist(i, end);

      final QuerySnapshot snapshot =
          await _recipesCollection
              .where(FieldPath.documentId, whereIn: batch)
              .get();

      recipes.addAll(
        snapshot.docs.map((doc) => Recipe.fromFirestore(doc)).toList(),
      );
    }

    return recipes;
  }

  // Get a single recipe by ID
  Future<Recipe?> getRecipe(String recipeId) async {
    final doc = await _recipesCollection.doc(recipeId).get();
    if (doc.exists) {
      return Recipe.fromFirestore(doc);
    }
    return null;
  }

  // Get user document
  Future<DocumentSnapshot?> getUserDocument(String userId) async {
    return await _usersCollection.doc(userId).get();
  }

  // Update user document
  Future<void> updateUserDocument(
    String userId,
    Map<String, dynamic> data,
  ) async {
    await _usersCollection.doc(userId).update(data);
  }

  // Get user recipes as a list (not a stream)
  Future<List<Recipe>> getUserRecipesList(String userId) async {
    final QuerySnapshot snapshot =
        await _recipesCollection
            .where('userId', isEqualTo: userId)
            .orderBy('createdAt', descending: true)
            .get();

    return snapshot.docs.map((doc) => Recipe.fromFirestore(doc)).toList();
  }

  // Add a new recipe
  Future<Recipe> addRecipe(Recipe recipe) async {
    try {
      // Validate required fields
      if (recipe.title.isEmpty) {
        throw Exception('Recipe title is required');
      }
      if (recipe.userId.isEmpty) {
        throw Exception('User ID is required');
      }
      if (recipe.ingredients.isEmpty) {
        throw Exception('At least one ingredient is required');
      }
      if (recipe.instructions.isEmpty) {
        throw Exception('At least one instruction is required');
      }

      // Create a new document reference if ID is empty
      final String recipeId =
          recipe.id.isEmpty ? _recipesCollection.doc().id : recipe.id;
      final recipeWithId = recipe.copyWith(id: recipeId);

      // Log the operation
      FirebaseService.logFirestoreOperation(
        'add',
        'recipes',
        recipeId,
        recipeWithId.toFirestore(),
      );

      // Ensure the recipes collection exists by trying to create a test document
      try {
        await _recipesCollection.doc('_test').set({
          'test': true,
          'timestamp': Timestamp.now(),
        });
        await _recipesCollection.doc('_test').delete();
      } catch (e) {
        developer.log(
          'Error creating test document: $e',
          name: 'RecipeService',
          error: e,
        );
      }

      // Add the recipe to Firestore
      await _recipesCollection.doc(recipeId).set(recipeWithId.toFirestore());

      // Update user's recipe count
      await _updateUserRecipeCount(recipe.userId);

      return recipeWithId;
    } catch (e, stackTrace) {
      developer.log(
        'Error adding recipe: $e',
        name: 'RecipeService',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  // Update an existing recipe
  Future<Recipe> updateRecipe(Recipe recipe) async {
    developer.log(
      'RecipeService: Attempting to update recipe ${recipe.id} in Firestore. Data: ${recipe.toFirestore()}',
      name: 'RecipeService',
    );
    try {
      await _recipesCollection.doc(recipe.id).update(recipe.toFirestore());
      developer.log(
        'RecipeService: Successfully updated recipe ${recipe.id}',
        name: 'RecipeService',
      );
    } catch (e, stackTrace) {
      developer.log(
        'RecipeService: ERROR updating recipe ${recipe.id} in Firestore: $e',
        name: 'RecipeService',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow; // Re-throw the error so the calling function knows about it
    }
    return recipe;
  }

  // Delete a recipe
  Future<void> deleteRecipe(String recipeId) async {
    // Get the recipe to check if it has an image and if it's a favorite
    final recipe = await getRecipe(recipeId);

    if (recipe != null) {
      // Delete the image from storage if it exists
      if (recipe.imageUrl.isNotEmpty) {
        try {
          final ref = _storage.refFromURL(recipe.imageUrl);
          await ref.delete();
        } catch (e) {
          // Image might not exist or other error, continue with deletion
          developer.log('Error deleting image: $e', name: 'RecipeService');
        }
      }

      // Delete the recipe document
      await _recipesCollection.doc(recipeId).delete();

      // If the deleted recipe was a favorite, update the user's favorites
      if (recipe.isFavorite) {
        await updateUserFavorites(recipe.userId, recipe.id, false);
      } // Note: updateUserFavorites also updates favoriteCount

      // Update user's recipe count (this only updates recipeCount)
      await _updateUserRecipeCount(recipe.userId);
    }
  }

  // Toggle favorite status
  Future<Recipe> toggleFavorite(Recipe recipe) async {
    final updatedRecipe = recipe.copyWith(isFavorite: !recipe.isFavorite);
    await _recipesCollection.doc(recipe.id).update({
      'isFavorite': updatedRecipe.isFavorite,
    });

    // Update user's favorite recipes list
    await updateUserFavorites(
      recipe.userId,
      recipe.id,
      updatedRecipe.isFavorite,
    );

    return updatedRecipe;
  }

  // Update user's favorite recipes
  Future<void> updateUserFavorites(
    String userId,
    String recipeId,
    bool isFavorite,
  ) async {
    try {
      FirebaseService.logFirestoreOperation('read', 'users', userId);
      final userDoc = await _usersCollection.doc(userId).get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        // Use a Set for uniqueness
        final Set<String> favoriteRecipesSet = Set<String>.from(
          userData['favoriteRecipes'] ?? [],
        );

        if (isFavorite) {
          // Add to set (automatically handles duplicates)
          favoriteRecipesSet.add(recipeId);
        } else {
          // Remove from set
          favoriteRecipesSet.remove(recipeId);
        }

        // Convert back to list for Firestore
        final List<String> updatedFavoriteList = favoriteRecipesSet.toList();

        final updates = {
          'favoriteRecipes': updatedFavoriteList, // Save the unique list
          'lastUpdated': Timestamp.fromDate(DateTime.now()),
          'favoriteCount':
              updatedFavoriteList.length, // Count based on the unique list
        };

        FirebaseService.logFirestoreOperation(
          'update',
          'users',
          userId,
          updates,
        );
        await _usersCollection.doc(userId).update(updates);
      }
    } catch (e) {
      developer.log(
        'Error updating user favorites: $e',
        name: 'RecipeService',
        error: e,
      );
      rethrow;
    }
  }

  // Update user's recipe count
  Future<void> _updateUserRecipeCount(String userId) async {
    try {
      FirebaseService.logFirestoreOperation('count', 'recipes', null, {
        'userId': userId,
      });
      final recipeCount = await _recipesCollection
          .where('userId', isEqualTo: userId)
          .count()
          .get()
          .then((value) => value.count);

      final updates = {
        'recipeCount': recipeCount,
        'lastUpdated': Timestamp.fromDate(DateTime.now()),
      };

      FirebaseService.logFirestoreOperation('update', 'users', userId, updates);
      await _usersCollection.doc(userId).update(updates);
    } catch (e) {
      developer.log(
        'Error updating user recipe count: $e',
        name: 'RecipeService',
        error: e,
      );
    }
  }

  // Upload an image for a recipe
  Future<String> uploadRecipeImage(File imageFile, String userId) async {
    final String fileName =
        '${userId}_${const Uuid().v4()}${path.extension(imageFile.path)}';
    final Reference storageRef = _storage.ref().child(
      'recipeImages/$userId/$fileName',
    );

    final UploadTask uploadTask = storageRef.putFile(imageFile);
    final TaskSnapshot taskSnapshot = await uploadTask;

    return await taskSnapshot.ref.getDownloadURL();
  }

  // Search recipes by title, ingredients, or tags
  Future<List<Recipe>> searchRecipes(String userId, String query) async {
    // Convert query to lowercase for case-insensitive search
    final lowerQuery = query.toLowerCase();

    // Get all user recipes
    final QuerySnapshot snapshot =
        await _recipesCollection.where('userId', isEqualTo: userId).get();

    // Filter recipes that match the query in title, ingredients, or tags
    return snapshot.docs.map((doc) => Recipe.fromFirestore(doc)).where((
      recipe,
    ) {
      final lowerTitle = recipe.title.toLowerCase();
      final lowerDescription = recipe.description.toLowerCase();
      final lowerIngredients =
          recipe.ingredients.map((i) => i.toLowerCase()).toList();
      final lowerTags = recipe.tags.map((t) => t.toLowerCase()).toList();

      return lowerTitle.contains(lowerQuery) ||
          lowerDescription.contains(lowerQuery) ||
          lowerIngredients.any((i) => i.contains(lowerQuery)) ||
          lowerTags.any((t) => t.contains(lowerQuery));
    }).toList();
  }

  // Extract recipe from a URL and create a new recipe
  Future<Recipe> createRecipeFromUrl(String url, String userId) async {
    try {
      // Extract recipe data from the URL
      final recipeData = await extractRecipeFromUrl(url);

      // Create a new recipe from the extracted data
      final recipe = Recipe(
        title: recipeData['title'] ?? 'Untitled Recipe',
        description: recipeData['description'] ?? '',
        ingredients: List<String>.from(recipeData['ingredients'] ?? []),
        instructions: List<String>.from(recipeData['instructions'] ?? []),
        imageUrl: recipeData['imageUrl'] ?? '',
        sourceUrl: url,
        userId: userId,
        prepTime: recipeData['prepTime'] ?? 0,
        cookTime: recipeData['cookTime'] ?? 0,
        servings: recipeData['servings'] ?? 1,
        tags: List<String>.from(recipeData['tags'] ?? []),
        source: recipeData['source'] ?? 'URL Import',
      );

      // Add the recipe to Firestore
      return await addRecipe(recipe);
    } catch (e) {
      developer.log(
        'Error creating recipe from URL: $e',
        name: 'RecipeService',
        error: e,
      );
      rethrow;
    }
  }

  // Extract recipe from a URL (this would need a backend service or API)
  Future<Map<String, dynamic>> extractRecipeFromUrl(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to load recipe from URL');
      }

      // Parse the HTML content
      final document = html_parser.parse(response.body);
      final body = document.body;

      // Helper function to clean text
      String cleanText(String text) {
        return text
            .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
            .trim();
      }

      // Helper function to extract text from a selector
      String? extractText(String selector) {
        final element = body?.querySelector(selector);
        return element != null ? cleanText(element.text) : null;
      }

      // Helper function to extract list items
      List<String> extractList(String selector) {
        final elements = body?.querySelectorAll(selector) ?? [];
        return elements
            .map((element) => cleanText(element.text))
            .where((text) => text.isNotEmpty)
            .toList();
      }

      // Extract recipe data using various selectors
      final title = extractText('h1') ?? 'Untitled Recipe';

      // Extract ingredients (try different common selectors)
      List<String> ingredients = [];
      final ingredientSelectors = [
        'ul.ingredients li',
        '.ingredients li',
        '.recipe-ingredients li',
        '[itemprop="recipeIngredient"]',
        '.ingredient-item',
      ];

      for (final selector in ingredientSelectors) {
        ingredients = extractList(selector);
        if (ingredients.isNotEmpty) break;
      }

      // Extract instructions (try different common selectors)
      List<String> instructions = [];
      final instructionSelectors = [
        'ol.instructions li',
        '.instructions li',
        '.recipe-instructions li',
        '[itemprop="recipeInstructions"]',
        '.step-item',
      ];

      for (final selector in instructionSelectors) {
        instructions = extractList(selector);
        if (instructions.isNotEmpty) break;
      }

      // Extract time information
      int prepTime = 0;
      int cookTime = 0;

      final prepTimeText =
          extractText('[itemprop="prepTime"]') ??
          extractText('.prep-time') ??
          extractText('.preparation-time');
      final cookTimeText =
          extractText('[itemprop="cookTime"]') ??
          extractText('.cook-time') ??
          extractText('.cooking-time');

      // Parse time strings to minutes
      if (prepTimeText != null) {
        final match = RegExp(r'(\d+)').firstMatch(prepTimeText);
        if (match != null) {
          prepTime = int.parse(match.group(1)!);
        }
      }

      if (cookTimeText != null) {
        final match = RegExp(r'(\d+)').firstMatch(cookTimeText);
        if (match != null) {
          cookTime = int.parse(match.group(1)!);
        }
      }

      // Extract servings
      int servings = 1;
      final servingsText =
          extractText('[itemprop="recipeYield"]') ??
          extractText('.servings') ??
          extractText('.yield');

      if (servingsText != null) {
        final match = RegExp(r'(\d+)').firstMatch(servingsText);
        if (match != null) {
          servings = int.parse(match.group(1)!);
        }
      }

      // Extract image URL
      String imageUrl = '';
      final imageElement =
          body?.querySelector('img[itemprop="image"]') ??
          body?.querySelector('.recipe-image img') ??
          body?.querySelector('.featured-image img');

      if (imageElement != null) {
        imageUrl = imageElement.attributes['src'] ?? '';
        // Convert relative URLs to absolute
        if (imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
          final uri = Uri.parse(url);
          imageUrl = '${uri.scheme}://${uri.host}$imageUrl';
        }
      }

      return {
        'title': title,
        'description': 'Recipe imported from URL',
        'ingredients': ingredients,
        'instructions': instructions,
        'prepTime': prepTime,
        'cookTime': cookTime,
        'servings': servings,
        'imageUrl': imageUrl,
        'tags': ['imported', 'url'],
        'source': 'URL Import',
      };
    } catch (e) {
      developer.log(
        'Error extracting recipe from URL: $e',
        name: 'RecipeService',
        error: e,
      );
      rethrow;
    }
  }
}
