// lib/providers/auth_provider.dart
import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart'
    show User; // for StreamSubscription<User?>

import 'package:spoonit/models/app_user.dart';
import 'package:spoonit/services/auth_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthState {
  final AuthStatus status;
  final AppUser? user;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
  });

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
        if (user != null) return authenticated(user!);
        return unauthenticated();
      case AuthStatus.unauthenticated:
        return unauthenticated();
      case AuthStatus.error:
        return error(errorMessage ?? 'Unknown error');
    }
  }
}

class AuthNotifier extends Notifier<AuthState> {
  AuthService? _authService;
  StreamSubscription<User?>? _sub;

  @override
  AuthState build() {
    // React to authService readiness and changes
    ref.listen<AsyncValue<AuthService>>(
      authServiceProvider,
      (prev, next) => _handleService(next),
      fireImmediately: true,
    );

    // Ensure resources are released when provider is disposed
    ref.onDispose(() {
      _sub?.cancel();
    });

    return const AuthState(status: AuthStatus.loading);
  }

  void _handleService(AsyncValue<AuthService> svcAsync) {
    svcAsync.when(
      data: (svc) {
        _authService = svc;

        // (Re)wire auth stream
        _sub?.cancel();
        _sub = _authService!.authChangesStream.listen(
          (u) async {
            if (kDebugMode) {
              developer.log('authChanges: uid=${u?.uid}', name: 'AuthNotifier');
            }
            if (u == null) {
              state = state.copyWith(
                status: AuthStatus.unauthenticated,
                user: null,
              );
            } else {
              await _loadUserData(u.uid);
            }
          },
          onError: (e, st) {
            state = state.copyWith(
              status: AuthStatus.error,
              errorMessage: e.toString(),
            );
          },
        );

        // If we already have a current user, load it once immediately
        final current = _authService!.currentUser;
        if (current == null) {
          state = state.copyWith(
            status: AuthStatus.unauthenticated,
            user: null,
          );
        } else {
          _loadUserData(current.uid);
        }
      },
      loading: () {
        state = state.copyWith(status: AuthStatus.loading);
      },
      error: (e, st) {
        state = AuthState(
          status: AuthStatus.error,
          errorMessage: 'Failed to init auth service: $e',
        );
      },
    );
  }

  Future<void> _loadUserData(String uid) async {
    try {
      state = state.copyWith(status: AuthStatus.loading);
      final userData = await _authService!.getUserData(uid);
      if (userData != null) {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: userData,
        );
      } else {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'User data not found',
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        developer.log(
          'loadUserData error',
          name: 'AuthNotifier',
          error: e,
          stackTrace: st,
        );
      }
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  // DRY helper for all login/registration flows
  Future<void> _completeLogin(
    Future<UserCredentialLite> Function() action,
  ) async {
    try {
      state = state.copyWith(status: AuthStatus.loading);
      final cred = await action();
      final uid = cred.uid;
      if (uid == null) throw Exception('No user in credential');
      final data = await _authService!.getUserData(uid);
      if (data == null) throw Exception('User data missing');
      state = state.copyWith(status: AuthStatus.authenticated, user: data);
    } catch (e, st) {
      if (kDebugMode) {
        developer.log(
          '_completeLogin error',
          name: 'AuthNotifier',
          error: e,
          stackTrace: st,
        );
      }
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      // Rethrow the exception so the UI can catch and handle it
      rethrow;
    }
  }

  // Public actions
  Future<void> registerWithEmailAndPassword(
    String name,
    String email,
    String password,
  ) {
    _ensureReady();
    return _completeLogin(
      () => _authService!.registerWithEmailAndPassword(email, password, name),
    );
  }

  Future<void> signInWithEmailAndPassword(String email, String password) {
    _ensureReady();
    return _completeLogin(
      () => _authService!.signInWithEmailAndPassword(email, password),
    );
  }

  Future<void> signInWithGoogle() {
    _ensureReady();
    return _completeLogin(_authService!.signInWithGoogle);
  }

  Future<void> signInWithFacebook() {
    _ensureReady();
    return _completeLogin(_authService!.signInWithFacebook);
  }

  Future<void> signInAnonymously() {
    _ensureReady();
    return _completeLogin(_authService!.signInAnonymously);
  }

  Future<void> signOut() async {
    _ensureReady();
    try {
      state = state.copyWith(status: AuthStatus.loading);
      await _authService!.signOut();
      state = state.copyWith(status: AuthStatus.unauthenticated, user: null);
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> updateProfile(String displayName, String? photoURL) async {
    _ensureReady();
    try {
      if (state.user == null) return;
      state = state.copyWith(status: AuthStatus.loading);
      await _authService!.updateUserProfile(
        displayName: displayName,
        photoURL: photoURL,
      );

      // Refresh current user data
      final uid = _authService!.currentUser?.uid;
      if (uid != null) {
        final userData = await _authService!.getUserData(uid);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: userData,
        );
      } else {
        state = state.copyWith(status: AuthStatus.unauthenticated, user: null);
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> deleteAccount() async {
    _ensureReady();
    try {
      if (state.user == null) return;
      state = state.copyWith(status: AuthStatus.loading);
      await _authService!.deleteAccount();
      state = state.copyWith(status: AuthStatus.unauthenticated, user: null);
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  // Optimistic local favorites
  void updateFavoriteLocally(String recipeId, bool isFavorite) {
    final u = state.user;
    if (u == null) return;
    final current = List<String>.from(u.favoriteRecipes);
    if (isFavorite && !current.contains(recipeId)) {
      current.add(recipeId);
    } else if (!isFavorite && current.contains(recipeId)) {
      current.remove(recipeId);
    }
    state = state.copyWith(user: u.copyWith(favoriteRecipes: current));
    // Optionally: enqueue background write & rollback on failure
  }

  void _ensureReady() {
    if (_authService == null) {
      throw StateError('AuthService not ready yet');
    }
  }

  /// Send password reset email
  Future<void> resetPassword(String email) async {
    _ensureReady();
    await _authService!.resetPassword(email);
  }
}

// Riverpod 3 NotifierProvider
final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  () => AuthNotifier(),
);

// Derived provider for convenience
final userDataProvider = Provider<AsyncValue<AppUser?>>((ref) {
  final s = ref.watch(authProvider);
  switch (s.status) {
    case AuthStatus.authenticated:
      return AsyncValue.data(s.user);
    case AuthStatus.error:
      return AsyncValue.error(
        s.errorMessage ?? 'Unknown error',
        StackTrace.current,
      );
    case AuthStatus.loading:
      return const AsyncValue.loading();
    case AuthStatus.initial:
    case AuthStatus.unauthenticated:
      return const AsyncValue.data(null);
  }
});
