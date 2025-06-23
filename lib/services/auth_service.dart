import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:recipe_keeper/models/app_user.dart';
import 'dart:developer' as developer;

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn =
      kIsWeb
          ? GoogleSignIn(
            clientId:
                '682017024777-on5ondrk2tinfabj0b4smecc16jpbuo4.apps.googleusercontent.com',
            scopes: ['email', 'profile'],
          )
          : GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Log authentication status - helpful for debugging
  void logAuthStatus() {
    final user = _auth.currentUser;
    if (user != null) {
      developer.log('User is authenticated', name: 'AuthService');
      developer.log('User ID: ${user.uid}', name: 'AuthService');
      developer.log('Email: ${user.email}', name: 'AuthService');
      developer.log('Display Name: ${user.displayName}', name: 'AuthService');
      developer.log(
        'Is Email Verified: ${user.emailVerified}',
        name: 'AuthService',
      );
    } else {
      developer.log('No user is authenticated!', name: 'AuthService');
    }
  }

  // Check permissions
  Future<bool> checkFirestorePermissions() async {
    try {
      // First check if we're authenticated
      if (_auth.currentUser == null) {
        developer.log(
          'Permission check: No authenticated user',
          name: 'AuthService',
        );
        return false;
      }

      // Try to access the users collection
      try {
        await _firestore.collection('users').doc(_auth.currentUser!.uid).get();
        developer.log(
          'Permission check: Can access user document',
          name: 'AuthService',
        );
        return true;
      } catch (e) {
        developer.log(
          'Permission check: Cannot access user document - $e',
          name: 'AuthService',
          error: e,
        );
        return false;
      }
    } catch (e) {
      developer.log(
        'Error checking permissions: $e',
        name: 'AuthService',
        error: e,
      );
      return false;
    }
  }

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Register with email and password
  Future<UserCredential> registerWithEmailAndPassword(
    String email,
    String password,
    String displayName,
  ) async {
    try {
      developer.log('Attempting to register: $email', name: 'AuthService');

      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      developer.log(
        'User registered with ID: ${credential.user?.uid}',
        name: 'AuthService',
      );

      // Update display name
      await credential.user?.updateDisplayName(displayName);

      // Create user document in Firestore
      if (credential.user != null) {
        await _createUserDocument(credential.user!, displayName);
      }

      return credential;
    } catch (e) {
      developer.log('Registration error: $e', name: 'AuthService', error: e);
      rethrow;
    }
  }

  // Sign in with email and password
  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      developer.log('Attempting to sign in: $email', name: 'AuthService');

      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      developer.log(
        'User signed in with ID: ${credential.user?.uid}',
        name: 'AuthService',
      );

      // Update last login timestamp
      if (credential.user != null) {
        await _firestore.collection('users').doc(credential.user!.uid).update({
          'lastLoginAt': Timestamp.fromDate(DateTime.now()),
        });
      }

      return credential;
    } catch (e) {
      developer.log('Sign in error: $e', name: 'AuthService', error: e);
      rethrow;
    }
  }

  // Sign in with Google
  Future<UserCredential> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw Exception('Google sign in aborted');
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      // Create or update user document in Firestore
      if (userCredential.user != null) {
        final userDoc =
            await _firestore
                .collection('users')
                .doc(userCredential.user!.uid)
                .get();

        if (!userDoc.exists) {
          await _createUserDocument(
            userCredential.user!,
            userCredential.user!.displayName ?? '',
          );
        } else {
          await _firestore
              .collection('users')
              .doc(userCredential.user!.uid)
              .update({'lastLoginAt': Timestamp.fromDate(DateTime.now())});
        }
      }

      return userCredential;
    } catch (e) {
      rethrow;
    }
  }

  // Sign in anonymously
  Future<UserCredential> signInAnonymously() async {
    try {
      developer.log('Attempting anonymous sign in', name: 'AuthService');

      final credential = await _auth.signInAnonymously();
      developer.log(
        'Anonymous user signed in with ID: ${credential.user?.uid}',
        name: 'AuthService',
      );

      // Create user document in Firestore for anonymous user
      if (credential.user != null) {
        final userDoc =
            await _firestore
                .collection('users')
                .doc(credential.user!.uid)
                .get();
        if (!userDoc.exists) {
          await _createUserDocument(credential.user!, 'Guest User');
        }
      }

      return credential;
    } catch (e) {
      developer.log(
        'Anonymous sign in error: $e',
        name: 'AuthService',
        error: e,
      );
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // Create user document in Firestore
  Future<void> _createUserDocument(User user, String displayName) async {
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      // Only create if it doesn't exist
      if (!userDoc.exists) {
        final appUser = AppUser(
          uid: user.uid,
          email: user.email ?? '',
          displayName: displayName,
          photoURL: user.photoURL,
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
          recipeCount: 0,
          favoriteCount: 0,
          sharedCount: 0,
          favoriteRecipes: [],
          preferences: {},
        );

        await _firestore
            .collection('users')
            .doc(user.uid)
            .set(appUser.toFirestore());
      } else {
        // Update last login time if user exists
        await _firestore.collection('users').doc(user.uid).update({
          'lastLoginAt': Timestamp.fromDate(DateTime.now()),
        });
      }
    } catch (e) {
      developer.log(
        'Error creating/updating user document: $e',
        name: 'AuthService',
        error: e,
      );
      rethrow;
    }
  }

  // Get user data from Firestore
  Future<AppUser?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return AppUser.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  // Update user profile
  Future<void> updateUserProfile({
    String? displayName,
    String? photoURL,
    Map<String, dynamic>? preferences,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    try {
      final Map<String, dynamic> updates = {};

      // Update Firebase Auth profile if needed
      if (displayName != null && displayName != user.displayName) {
        await user.updateDisplayName(displayName);
        updates['displayName'] = displayName;
      }
      if (photoURL != null && photoURL != user.photoURL) {
        await user.updatePhotoURL(photoURL);
        updates['photoURL'] = photoURL;
      }

      // Add preferences to Firestore updates if provided
      if (preferences != null) {
        updates['preferences'] = preferences;
      }

      // Update Firestore document if there are changes
      if (updates.isNotEmpty) {
        updates['lastUpdated'] = Timestamp.fromDate(DateTime.now());
        developer.log(
          'Updating Firestore user profile: $updates',
          name: 'AuthService',
        );
        await _firestore.collection('users').doc(user.uid).update(updates);
      }
    } catch (e) {
      developer.log(
        'Error updating user profile: $e',
        name: 'AuthService',
        error: e,
      );
      rethrow;
    }
  }

  // Change user password
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email;

    if (user == null || email == null) {
      throw Exception('User not authenticated or email is missing');
    }

    try {
      // Re-authenticate the user with their current password
      final AuthCredential credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );

      developer.log('Re-authenticating user...', name: 'AuthService');
      await user.reauthenticateWithCredential(credential);
      developer.log('Re-authentication successful.', name: 'AuthService');

      // If re-authentication is successful, update the password
      developer.log('Updating password...', name: 'AuthService');
      await user.updatePassword(newPassword);
      developer.log('Password updated successfully.', name: 'AuthService');
    } on FirebaseAuthException catch (e) {
      developer.log(
        'Error changing password: ${e.code} - ${e.message}',
        name: 'AuthService',
        error: e,
      );
      // Provide more specific error messages
      if (e.code == 'wrong-password') {
        throw Exception('Incorrect current password.');
      } else if (e.code == 'weak-password') {
        throw Exception('The new password is too weak.');
      } else if (e.code == 'requires-recent-login') {
        throw Exception(
          'This operation requires a recent login. Please sign out and sign back in.',
        );
      }
      throw Exception('An error occurred while changing password.');
    } catch (e) {
      developer.log(
        'Unexpected error changing password: $e',
        name: 'AuthService',
        error: e,
      );
      rethrow;
    }
  }

  // Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      rethrow;
    }
  }

  // Delete user account
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    try {
      // Delete user document from Firestore first
      await _firestore.collection('users').doc(user.uid).delete();

      // Delete user from Firebase Auth
      await user.delete();
    } catch (e) {
      // Handle potential errors, e.g., re-authentication required
      rethrow;
    }
  }
}
