import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:recipe_keeper/models/app_user.dart';
import 'package:recipe_keeper/screens/login_screen.dart';
import 'package:recipe_keeper/screens/register_screen.dart';
import 'package:recipe_keeper/screens/home_screen.dart';
import 'package:recipe_keeper/screens/recipe_detail_screen.dart';
import 'package:recipe_keeper/screens/create_recipe_screen.dart';
import 'package:recipe_keeper/screens/edit_recipe_screen.dart';
import 'package:recipe_keeper/screens/profile_screen.dart';
import 'package:recipe_keeper/screens/favorites_screen.dart';
import 'package:recipe_keeper/screens/import_recipe_screen.dart';
import 'package:recipe_keeper/screens/scan_recipe_screen.dart';
import 'package:recipe_keeper/screens/chat_screen.dart';
import 'package:recipe_keeper/screens/edit_profile_screen.dart';
import 'package:recipe_keeper/screens/custom_recipe_screen.dart';
import 'package:recipe_keeper/screens/welcome_screen.dart';

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/', // <-- ensure this is set to '/'
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final bool isLoggedIn = FirebaseAuth.instance.currentUser != null;
      final bool isGoingToLogin =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      // If not logged in and not going to login/register or welcome, redirect to welcome
      if (!isLoggedIn &&
          !isGoingToLogin &&
          state.matchedLocation != '/' &&
          state.matchedLocation != '/welcome') {
        return '/';
      }

      // If logged in and going to login/register/welcome, redirect to home
      if (isLoggedIn && (isGoingToLogin || state.matchedLocation == '/')) {
        return '/home';
      }

      // No redirect needed
      return null;
    },
    routes: [
      // Welcome screen as the initial route
      GoRoute(path: '/', builder: (context, state) => const WelcomeScreen()),

      // Authentication routes
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),

      // Main app shell with bottom navigation
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => HomeScreen(child: child),
        routes: [
          // Home tab
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeContent(),
          ),

          // Favorites tab
          GoRoute(
            path: '/favorites',
            builder: (context, state) => const FavoritesScreen(),
          ),

          // Profile tab
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
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
    ],
  );
}
