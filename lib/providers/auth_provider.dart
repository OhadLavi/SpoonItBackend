import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/models/app_user.dart';
import 'package:recipe_keeper/services/auth_service.dart';

// Define the possible authentication states
enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

// Define the authentication state class
class AuthState {
  final AuthStatus status;
  final AppUser? user;
  final String? errorMessage;

  AuthState({this.status = AuthStatus.initial, this.user, this.errorMessage});

  // Create a copy of the current state with updated fields
  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  // Add a when method to match what's being used in the profile screen
  T when<T>({
    required T Function() initial,
    required T Function() loading,
    required T Function(AppUser user) authenticated,
    required T Function() unauthenticated,
    required T Function(String message) error,
  }) {
    switch (status) {
      case AuthStatus.initial:
        return initial();
      case AuthStatus.loading:
        return loading();
      case AuthStatus.authenticated:
        if (user != null) {
          return authenticated(user!);
        }
        return unauthenticated();
      case AuthStatus.unauthenticated:
        return unauthenticated();
      case AuthStatus.error:
        return error(errorMessage ?? 'Unknown error');
    }
  }
}

// Define the authentication notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(AuthState()) {
    // Check if user is already logged in when the notifier is created
    checkAuthStatus();
  }

  // Update favorite recipes locally for optimistic UI updates
  void updateFavoriteLocally(String recipeId, bool isFavorite) {
    if (state.user == null) return;

    final currentFavorites = List<String>.from(state.user!.favoriteRecipes);

    if (isFavorite && !currentFavorites.contains(recipeId)) {
      currentFavorites.add(recipeId);
    } else if (!isFavorite && currentFavorites.contains(recipeId)) {
      currentFavorites.remove(recipeId);
    }

    // Update state with new favorites list
    final updatedUser = state.user!.copyWith(favoriteRecipes: currentFavorites);
    state = state.copyWith(user: updatedUser);
  }

  // Check the current authentication status
  Future<void> checkAuthStatus() async {
    try {
      state = state.copyWith(status: AuthStatus.loading);
      final user = _authService.currentUser;

      if (user != null) {
        final userData = await _authService.getUserData(user.uid);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: userData,
        );
      } else {
        state = state.copyWith(status: AuthStatus.unauthenticated);
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  // Register with email and password
  Future<void> registerWithEmailAndPassword(
    String name,
    String email,
    String password,
  ) async {
    try {
      state = state.copyWith(status: AuthStatus.loading);
      final userCredential = await _authService.registerWithEmailAndPassword(
        email,
        password,
        name,
      );

      if (userCredential.user != null) {
        final userData = await _authService.getUserData(
          userCredential.user!.uid,
        );
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: userData,
        );
      } else {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Registration failed',
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  // Sign in with email and password
  Future<void> signInWithEmailAndPassword(String email, String password) async {
    try {
      state = state.copyWith(status: AuthStatus.loading);
      final userCredential = await _authService.signInWithEmailAndPassword(
        email,
        password,
      );

      if (userCredential.user != null) {
        final userData = await _authService.getUserData(
          userCredential.user!.uid,
        );
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: userData,
        );
      } else {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Sign in failed',
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  // Sign in with Google
  Future<void> signInWithGoogle() async {
    try {
      state = state.copyWith(status: AuthStatus.loading);
      final userCredential = await _authService.signInWithGoogle();

      if (userCredential.user != null) {
        final userData = await _authService.getUserData(
          userCredential.user!.uid,
        );
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: userData,
        );
      } else {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Google sign in failed',
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  // Sign in anonymously
  Future<void> signInAnonymously() async {
    try {
      state = state.copyWith(status: AuthStatus.loading);
      final userCredential = await _authService.signInAnonymously();

      if (userCredential.user != null) {
        final userData = await _authService.getUserData(
          userCredential.user!.uid,
        );
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: userData,
        );
      } else {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Anonymous sign in failed',
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      state = state.copyWith(status: AuthStatus.loading);
      await _authService.signOut();
      state = state.copyWith(status: AuthStatus.unauthenticated, user: null);
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  // Update user profile
  Future<void> updateProfile(String displayName, String? photoURL) async {
    try {
      if (state.user == null) return;

      state = state.copyWith(status: AuthStatus.loading);
      await _authService.updateUserProfile(
        displayName: displayName,
        photoURL: photoURL,
      );

      final user = _authService.currentUser;
      if (user != null) {
        final userData = await _authService.getUserData(user.uid);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: userData,
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  // Delete account
  Future<void> deleteAccount() async {
    try {
      if (state.user == null) return;

      state = state.copyWith(status: AuthStatus.loading);
      await _authService.deleteAccount();
      state = state.copyWith(status: AuthStatus.unauthenticated, user: null);
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}

// Provider for the authentication state
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = AuthService();
  return AuthNotifier(authService);
});

// Provider for user data
final userDataProvider = Provider<AsyncValue<AppUser?>>((ref) {
  final authState = ref.watch(authProvider);

  if (authState.status == AuthStatus.authenticated && authState.user != null) {
    return AsyncValue.data(authState.user);
  } else if (authState.status == AuthStatus.error) {
    return AsyncValue.error(
      authState.errorMessage ?? 'Unknown error',
      StackTrace.current,
    );
  } else if (authState.status == AuthStatus.loading) {
    return const AsyncValue.loading();
  } else {
    return const AsyncValue.data(null);
  }
});
