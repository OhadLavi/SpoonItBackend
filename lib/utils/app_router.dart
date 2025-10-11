import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:spoonit/models/app_user.dart';
import 'package:spoonit/screens/login_screen.dart';
import 'package:spoonit/screens/register_screen.dart';
import 'package:spoonit/screens/home_screen.dart';
import 'package:spoonit/screens/recipe_detail_screen.dart';
import 'package:spoonit/screens/create_recipe_screen.dart';
import 'package:spoonit/screens/edit_recipe_screen.dart';
import 'package:spoonit/screens/profile_screen.dart';
import 'package:spoonit/screens/favorites_screen.dart';
import 'package:spoonit/screens/import_recipe_screen.dart';
import 'package:spoonit/screens/scan_recipe_screen.dart';
import 'package:spoonit/screens/chat_screen.dart';
import 'package:spoonit/screens/edit_profile_screen.dart';
import 'package:spoonit/screens/custom_recipe_screen.dart';
import 'package:spoonit/screens/search_screen.dart';
import 'package:spoonit/screens/shopping_list_screen.dart';
import 'package:spoonit/screens/support_screen.dart';
import 'package:spoonit/screens/terms_privacy_screen.dart';
import 'package:spoonit/screens/category_recipes_screen.dart';

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/login', // <-- redirect to login directly
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final bool isLoggedIn = FirebaseAuth.instance.currentUser != null;
      final bool isGoingToLogin =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      // If not logged in and not going to login/register, redirect to login
      if (!isLoggedIn && !isGoingToLogin) {
        return '/login';
      }

      // If logged in and going to login/register, redirect to home
      if (isLoggedIn && isGoingToLogin) {
        return '/home';
      }

      // No redirect needed
      return null;
    },
    routes: [
      // Authentication routes
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),

      // Top-level app routes
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/my-recipes',
        builder: (context, state) => const FavoritesScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/shopping-list',
        builder: (context, state) => const ShoppingListScreen(),
      ),

      // Recipe detail screen
      GoRoute(
        path: '/recipe/:id',
        builder:
            (context, state) =>
                RecipeDetailScreen(recipeId: state.pathParameters['id']!),
      ),

      // Add recipe screen
      GoRoute(
        path: '/add-recipe',
        builder: (context, state) => const CreateRecipeScreen(),
      ),

      // Edit recipe screen
      GoRoute(
        path: '/edit-recipe/:id',
        builder:
            (context, state) =>
                EditRecipeScreen(recipeId: state.pathParameters['id']!),
      ),

      // Import recipe screen
      GoRoute(
        path: '/import-recipe',
        builder: (context, state) => const ImportRecipeScreen(),
      ),

      // Scan recipe screen
      GoRoute(
        path: '/scan-recipe',
        builder: (context, state) => const ScanRecipeScreen(),
      ),

      // Chat screen
      GoRoute(path: '/chat', builder: (context, state) => const ChatScreen()),

      // Search screen
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),

      // Category recipes screen
      GoRoute(
        path: '/category/:name/:id',
        builder: (context, state) =>
            CategoryRecipesScreen(
              categoryName: state.pathParameters['name']!,
              categoryId: state.pathParameters['id']!,
            ),
      ),

      // Edit Profile Screen (Outside the ShellRoute)
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) {
          // Extract the user data passed as extra
          final user = state.extra as AppUser?;
          if (user == null) {
            // Handle error case - maybe redirect to profile or show error page
            // For now, just return a placeholder
            return const Scaffold(
              body: Center(child: Text('Error: User data missing')),
            );
          }
          return EditProfileScreen(user: user);
        },
      ),

      // Change Password Screen is now accessed via Edit Profile screen
      // GoRoute(
      //  path: '/profile/change-password',
      //  builder: (context, state) => const ChangePasswordScreen(),
      // ),
      GoRoute(
        path: '/custom_recipe',
        builder: (context, state) => const CustomRecipeScreen(),
      ),

      // Support screen
      GoRoute(
        path: '/support',
        builder: (context, state) => const SupportScreen(),
      ),

      // Terms and privacy screen
      GoRoute(
        path: '/terms-privacy',
        builder: (context, state) => const TermsPrivacyScreen(),
      ),

    ],
  );
}
