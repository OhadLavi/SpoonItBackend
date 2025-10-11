// lib/services/auth_service.dart
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:spoonit/models/app_user.dart';
import 'package:spoonit/services/input_sanitizer_service.dart';
import 'package:spoonit/services/audit_logger_service.dart';

/// Build-time define for web client id
const String kGoogleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue:
      '682017024777-qr6b3m3v5q99jeahqe7ru6f1qjcnd078.apps.googleusercontent.com',
);

// Minimal wrapper so providers don’t depend on Firebase’s UserCredential directly
class UserCredentialLite {
  final String? uid;
  const UserCredentialLite(this.uid);
}

final firestoreProvider = Provider<FirebaseFirestore>(
  (_) => FirebaseFirestore.instance,
);
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (_) => FirebaseAuth.instance,
);

final authServiceProvider = FutureProvider<AuthService>((ref) async {
  if (kDebugMode) {
    developer.log('Creating AuthService instance', name: 'AuthService');
  }

  final auth = ref.read(firebaseAuthProvider);
  final fs = ref.read(firestoreProvider);

  final service = AuthService(auth: auth, firestore: fs);

  if (kDebugMode) {
    developer.log('AuthService created', name: 'AuthService');
  }
  return service;
});

class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  late final GoogleSignIn _googleSignIn;

  // Typed reference only for reads; partial updates use untyped doc()
  late final CollectionReference<AppUser> _usersRefTyped;

  AuthService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  }) : _auth = auth,
       _firestore = firestore {
    // Ensure Firebase is initialized (throws if not)
    _auth.app;

    _googleSignIn =
        kIsWeb
            ? GoogleSignIn(
              clientId: kGoogleWebClientId,
              scopes: const ['email', 'profile'],
            )
            : GoogleSignIn();

    _usersRefTyped = _firestore
        .collection('users')
        .withConverter<AppUser>(
          fromFirestore: (snap, _) => AppUser.fromFirestore(snap),
          toFirestore: (user, _) => user.toFirestore(),
        );
  }

  User? get currentUser => _auth.currentUser;

  // Prefer userChanges() to catch profile/token refresh as well
  Stream<User?> get authChangesStream => _auth.userChanges();

  // -------------------- Auth flows --------------------

  Future<UserCredentialLite> registerWithEmailAndPassword(
    String email,
    String password,
    String displayName,
  ) async {
    try {
      // Sanitize inputs
      final sanitizedEmail = InputSanitizer.sanitizeEmail(email);
      final sanitizedDisplayName = InputSanitizer.sanitizeDisplayName(
        displayName,
      );

      // Log registration attempt
      AuditLogger.logRegistrationAttempt(sanitizedEmail, 'email');

      if (kDebugMode) {
        developer.log('Registering email=$sanitizedEmail', name: 'AuthService');
      }

      final cred = await _auth.createUserWithEmailAndPassword(
        email: sanitizedEmail,
        password: password,
      );

      await cred.user?.updateDisplayName(sanitizedDisplayName);

      if (cred.user != null) {
        await _createOrUpdateUserDocumentOnLogin(
          cred.user!,
          sanitizedDisplayName,
        );
        AuditLogger.logRegistrationSuccess(sanitizedEmail, 'email');
      }
      return UserCredentialLite(cred.user?.uid);
    } catch (e) {
      AuditLogger.logRegistrationFailure(email, 'email', e.toString());
      if (kDebugMode) {
        developer.log('Registration error', name: 'AuthService', error: e);
      }
      rethrow;
    }
  }

  Future<UserCredentialLite> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      // Sanitize email input
      final sanitizedEmail = InputSanitizer.sanitizeEmail(email);

      // Log login attempt
      AuditLogger.logLoginAttempt(sanitizedEmail, 'email');

      if (kDebugMode) {
        developer.log('Sign in email=$sanitizedEmail', name: 'AuthService');
      }
      final cred = await _auth.signInWithEmailAndPassword(
        email: sanitizedEmail,
        password: password,
      );

      if (cred.user != null) {
        await _firestore.collection('users').doc(cred.user!.uid).set({
          'lastLoginAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        AuditLogger.logLoginSuccess(sanitizedEmail, 'email');
      }
      return UserCredentialLite(cred.user?.uid);
    } catch (e) {
      AuditLogger.logLoginFailure(email, 'email', e.toString());
      if (kDebugMode) {
        developer.log('Sign in error', name: 'AuthService', error: e);
      }
      rethrow;
    }
  }

  Future<UserCredentialLite> signInWithGoogle() async {
    try {
      // Log Google sign-in attempt
      AuditLogger.logLoginAttempt('google_user', 'google');

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw Exception('Google sign-in aborted');
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await _auth.signInWithCredential(credential);

      if (userCred.user != null) {
        final doc =
            await _firestore.collection('users').doc(userCred.user!.uid).get();
        if (!doc.exists) {
          final sanitizedDisplayName = InputSanitizer.sanitizeDisplayName(
            userCred.user!.displayName ?? '',
          );
          await _createOrUpdateUserDocumentOnLogin(
            userCred.user!,
            sanitizedDisplayName,
          );
        } else {
          await _firestore.collection('users').doc(userCred.user!.uid).set({
            'lastLoginAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        AuditLogger.logLoginSuccess(googleUser.email, 'google');
      }

      return UserCredentialLite(userCred.user?.uid);
    } on StateError catch (e) {
      AuditLogger.logLoginFailure('google_user', 'google', e.toString());
      if (kDebugMode) {
        developer.log(
          'Google sign-in state error',
          name: 'AuthService',
          error: e,
        );
      }
      if (_auth.currentUser != null) {
        throw Exception('Please refresh the page and try again');
      }
      rethrow;
    } catch (e) {
      AuditLogger.logLoginFailure('google_user', 'google', e.toString());
      if (kDebugMode) {
        developer.log('Google sign-in error', name: 'AuthService', error: e);
      }
      rethrow;
    }
  }

  Future<UserCredentialLite> signInWithFacebook() async {
    try {
      if (kDebugMode) {
        developer.log('Facebook sign-in', name: 'AuthService');
      }

      // For now, we'll use a placeholder implementation
      // In a real app, you would integrate with Facebook SDK
      throw Exception(
        'Facebook login not yet implemented. Please use Google or email login.',
      );
    } catch (e) {
      if (kDebugMode) {
        developer.log('Facebook sign-in error', name: 'AuthService', error: e);
      }
      rethrow;
    }
  }

  Future<UserCredentialLite> signInAnonymously() async {
    try {
      if (kDebugMode) {
        developer.log('Anonymous sign-in', name: 'AuthService');
      }
      final cred = await _auth.signInAnonymously();

      if (cred.user != null) {
        final doc =
            await _firestore.collection('users').doc(cred.user!.uid).get();
        if (!doc.exists) {
          await _createOrUpdateUserDocumentOnLogin(cred.user!, 'Guest User');
        } else {
          await _firestore.collection('users').doc(cred.user!.uid).set({
            'lastLoginAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      return UserCredentialLite(cred.user?.uid);
    } catch (e) {
      if (kDebugMode) {
        developer.log('Anonymous sign-in error', name: 'AuthService', error: e);
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Ignore if not signed-in with Google
    }
    await _auth.signOut();
  }

  // -------------------- User profile & persistence --------------------

  Future<void> _createOrUpdateUserDocumentOnLogin(
    User user,
    String displayName,
  ) async {
    // Sanitize user data before storing
    final sanitizedEmail = InputSanitizer.sanitizeEmail(user.email ?? '');
    final sanitizedDisplayName = InputSanitizer.sanitizeDisplayName(
      displayName,
    );
    final sanitizedPhotoUrl =
        user.photoURL != null
            ? InputSanitizer.sanitizeUrl(user.photoURL!)
            : null;

    // Use untyped doc for server timestamps and partial merges
    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'email': sanitizedEmail,
      'displayName': sanitizedDisplayName,
      'photoURL': sanitizedPhotoUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
      'recipeCount': 0,
      'favoriteCount': 0,
      'sharedCount': 0,
      'favoriteRecipes': <String>[],
      'preferences': <String, dynamic>{},
    }, SetOptions(merge: true));
  }

  Future<AppUser?> getUserData(String uid) async {
    try {
      final doc = await _usersRefTyped.doc(uid).get();
      return doc.data();
    } catch (e, st) {
      if (kDebugMode) {
        developer.log(
          'getUserData error',
          name: 'AuthService',
          error: e,
          stackTrace: st,
        );
      }
      rethrow;
    }
  }

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
      final List<String> updatedFields = [];

      // Sanitize and update Firebase Auth profile if needed
      if (displayName != null && displayName != user.displayName) {
        final sanitizedDisplayName = InputSanitizer.sanitizeDisplayName(
          displayName,
        );
        await user.updateDisplayName(sanitizedDisplayName);
        updates['displayName'] = sanitizedDisplayName;
        updatedFields.add('displayName');
      }
      if (photoURL != null && photoURL != user.photoURL) {
        final sanitizedPhotoUrl = InputSanitizer.sanitizeUrl(photoURL);
        await user.updatePhotoURL(sanitizedPhotoUrl);
        updates['photoURL'] = sanitizedPhotoUrl;
        updatedFields.add('photoURL');
      }

      if (preferences != null) {
        updates['preferences'] = _sanitizePreferences(preferences);
        updatedFields.add('preferences');
      }

      if (updates.isNotEmpty) {
        updates['lastUpdated'] = FieldValue.serverTimestamp();
        await _firestore
            .collection('users')
            .doc(user.uid)
            .set(updates, SetOptions(merge: true));

        // Log profile update
        AuditLogger.logProfileUpdate(user.uid, updatedFields);
      }

      // Ensure auth stream emits fresh data
      await user.reload();
    } catch (e) {
      if (kDebugMode) {
        developer.log('updateUserProfile error', name: 'AuthService', error: e);
      }
      rethrow;
    }
  }

  Map<String, dynamic> _sanitizePreferences(Map<String, dynamic> raw) {
    // Allow-list keys & basic type checks
    const allowed = {
      'language',
      'themeMode',
      'notifications',
      'measurementSystem',
    };
    final out = <String, dynamic>{};
    for (final e in raw.entries) {
      if (!allowed.contains(e.key)) continue;
      final v = e.value;
      if (v is String || v is bool || v is num || v == null) {
        out[e.key] = v;
      }
    }
    return out;
  }

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
      final cred = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPassword);

      // Log password change
      AuditLogger.logPasswordChange(user.uid);
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        developer.log(
          'changePassword error: ${e.code}',
          name: 'AuthService',
          error: e,
        );
      }
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
      if (kDebugMode) {
        developer.log(
          'changePassword unexpected',
          name: 'AuthService',
          error: e,
        );
      }
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    final sanitizedEmail = InputSanitizer.sanitizeEmail(email);
    await _auth.sendPasswordResetEmail(email: sanitizedEmail);
    AuditLogger.logPasswordReset(sanitizedEmail);
  }

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    try {
      // Log account deletion
      AuditLogger.logAccountDeletion(user.uid, user.email ?? '');

      // Delete Firestore first
      await _firestore.collection('users').doc(user.uid).delete();

      // Then delete auth user
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw Exception('Please reauthenticate to delete your account.');
      }
      rethrow;
    }
  }

  /// Send password reset email
  Future<void> resetPassword(String email) async {
    try {
      final sanitizedEmail = InputSanitizer.sanitizeEmail(email);
      await _auth.sendPasswordResetEmail(email: sanitizedEmail);
      AuditLogger.logPasswordReset(sanitizedEmail);
    } on FirebaseAuthException catch (e) {
      throw Exception('Failed to send password reset email: ${e.message}');
    }
  }
}
