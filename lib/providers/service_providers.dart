import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spoonit/services/auth_service.dart';
import 'package:spoonit/services/chat_service.dart';
import 'package:spoonit/services/recipe_extraction_service.dart';
import 'package:spoonit/services/shopping_list_service.dart';
import 'package:spoonit/services/category_service.dart';
import 'package:spoonit/services/image_service.dart';
import 'package:spoonit/services/error_handler_service.dart';

/// Service Providers for consistent service access across the application
///
/// This file centralizes all service providers to ensure:
/// - Consistent service instantiation
/// - Proper dependency injection
/// - Easy testing and mocking
/// - Single source of truth for services

// Firebase Providers
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);
final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

// Core Services
final authServiceProvider = Provider<AuthService>((ref) {
  final auth = ref.read(firebaseAuthProvider);
  final firestore = ref.read(firestoreProvider);
  return AuthService(auth: auth, firestore: firestore);
});
final chatServiceProvider = Provider<ChatService>((ref) => ChatService());
final recipeExtractionServiceProvider = Provider<RecipeExtractionService>(
  (ref) => RecipeExtractionService(),
);
final shoppingListServiceProvider = Provider<ShoppingListService>(
  (ref) => ShoppingListService(),
);
final categoryServiceProvider = Provider<CategoryService>(
  (ref) => CategoryService(),
);
final imageServiceProvider = Provider<ImageService>((ref) => ImageService());
final errorHandlerServiceProvider = Provider<ErrorHandlerService>(
  (ref) => ErrorHandlerService(),
);

// Service Access Helpers
/// Helper class to access services consistently
class ServiceAccess {
  static AuthService auth(WidgetRef ref) => ref.read(authServiceProvider);
  static ChatService chat(WidgetRef ref) => ref.read(chatServiceProvider);
  static RecipeExtractionService recipeExtraction(WidgetRef ref) =>
      ref.read(recipeExtractionServiceProvider);
  static ShoppingListService shoppingList(WidgetRef ref) =>
      ref.read(shoppingListServiceProvider);
  static CategoryService category(WidgetRef ref) =>
      ref.read(categoryServiceProvider);
  static ImageService image(WidgetRef ref) => ref.read(imageServiceProvider);
  static ErrorHandlerService errorHandler(WidgetRef ref) =>
      ref.read(errorHandlerServiceProvider);
}

/// Service Result Pattern for consistent error handling
///
/// This pattern ensures all service methods return a consistent result type
/// that can be easily handled in UI components
class ServiceResult<T> {
  final T? data;
  final String? error;
  final bool isSuccess;

  const ServiceResult._({this.data, this.error, required this.isSuccess});

  factory ServiceResult.success(T data) =>
      ServiceResult._(data: data, isSuccess: true);

  factory ServiceResult.error(String error) =>
      ServiceResult._(error: error, isSuccess: false);

  /// Fold pattern for handling success and error cases
  R fold<R>(R Function(String error) onError, R Function(T data) onSuccess) {
    if (isSuccess && data != null) {
      return onSuccess(data as T);
    } else {
      return onError(error ?? 'Unknown error');
    }
  }
}
