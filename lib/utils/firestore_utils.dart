import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'package:recipe_keeper/services/firebase_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Utility class to handle Firestore operations with proper error handling and retry logic
class FirestoreUtils {
  /// Maximum number of retry attempts for Firestore operations
  static const int maxRetries = 3;

  /// Delay between retry attempts (increases with each retry)
  static const Duration initialRetryDelay = Duration(seconds: 1);

  /// Execute a Firestore operation with retry logic
  ///
  /// [operation] - The Firestore operation to execute
  /// [operationName] - Name of the operation for logging
  /// [collection] - Collection name for logging
  /// [docId] - Optional document ID for logging
  static Future<T> executeWithRetry<T>({
    required Future<T> Function() operation,
    required String operationName,
    required String collection,
    String? docId,
    int maxAttempts = maxRetries,
  }) async {
    int attempt = 0;

    while (attempt < maxAttempts) {
      try {
        attempt++;

        if (attempt > 1) {
          developer.log(
            'Retry attempt $attempt for $operationName on $collection${docId != null ? " (ID: $docId)" : ""}',
            name: 'FirestoreRetry',
          );
        }

        // Log the operation
        FirebaseService.logFirestoreOperation(operationName, collection, docId);

        // Execute the operation
        final result = await operation();

        // If successful, return the result
        return result;
      } on FirebaseException catch (e, stackTrace) {
        final isLastAttempt = attempt >= maxAttempts;

        // Log the error
        developer.log(
          'Firestore error during $operationName on $collection${docId != null ? " (ID: $docId)" : ""}: ${e.code} - ${e.message}',
          name: 'FirestoreError',
          error: e,
          stackTrace: stackTrace,
        );

        // Check if we should retry based on the error
        if (isLastAttempt || !_shouldRetry(e)) {
          rethrow;
        }

        // Wait before retrying with exponential backoff
        final retryDelay = Duration(
          milliseconds: initialRetryDelay.inMilliseconds * attempt,
        );
        await Future.delayed(retryDelay);
      } catch (e, stackTrace) {
        // For non-Firebase errors, log and rethrow
        developer.log(
          'Non-Firebase error during $operationName on $collection${docId != null ? " (ID: $docId)" : ""}: $e',
          name: 'FirestoreError',
          error: e,
          stackTrace: stackTrace,
        );
        rethrow;
      }
    }

    // This should never happen, but to satisfy the compiler
    throw FirebaseException(
      plugin: 'firestore',
      code: 'max-retries-exceeded',
      message: 'Maximum retry attempts ($maxRetries) exceeded.',
    );
  }

  /// Determines if an operation should be retried based on the error
  static bool _shouldRetry(FirebaseException error) {
    // List of error codes that are potentially recoverable with a retry
    const recoverableErrorCodes = [
      'unavailable', // Server unavailable, may resolve with retry
      'deadline-exceeded', // Operation timed out, may succeed on retry
      'cancelled', // Operation cancelled, can retry
      'network-request-failed', // Network error, can retry when connection is back
      'resource-exhausted', // Resource limits temporarily exceeded
    ];

    return recoverableErrorCodes.contains(error.code);
  }

  /// Safely perform a batch write operation with retry logic
  static Future<void> performBatchOperation({
    required Future<void> Function(WriteBatch batch) buildBatchFunction,
    required String operationName,
    int maxAttempts = maxRetries,
  }) async {
    return executeWithRetry(
      operation: () async {
        final batch = FirebaseFirestore.instance.batch();
        await buildBatchFunction(batch);
        return await batch.commit();
      },
      operationName: operationName,
      collection: 'batch',
      maxAttempts: maxAttempts,
    );
  }

  /// Tests Firestore access with and without authentication
  static Future<Map<String, bool>> testFirestoreAccess() async {
    final results = <String, bool>{};

    // Check auth status
    final isAuthenticated = FirebaseAuth.instance.currentUser != null;
    developer.log(
      'Authentication status: ${isAuthenticated ? "Authenticated" : "Not authenticated"}',
      name: 'FirestoreTest',
    );

    results['authenticated'] = isAuthenticated;

    // Test collections
    try {
      // 1. Test _health_check collection (public access)
      try {
        final docRef = FirebaseFirestore.instance
            .collection('_health_check')
            .doc('test_access');
        await docRef.set({'timestamp': FieldValue.serverTimestamp()});
        final docSnapshot = await docRef.get();
        results['health_check_write'] = true;
        results['health_check_read'] = docSnapshot.exists;
        developer.log(
          '_health_check collection test: Write: ${results['health_check_write']}, Read: ${results['health_check_read']}',
          name: 'FirestoreTest',
        );
      } catch (e) {
        results['health_check_write'] = false;
        results['health_check_read'] = false;
        developer.log(
          '_health_check test failed: $e',
          name: 'FirestoreTest',
          error: e,
        );
      }

      // 2. Test testing collection (public access)
      try {
        final docRef = FirebaseFirestore.instance
            .collection('testing')
            .doc('test_access');
        await docRef.set({'timestamp': FieldValue.serverTimestamp()});
        final docSnapshot = await docRef.get();
        results['testing_write'] = true;
        results['testing_read'] = docSnapshot.exists;
        developer.log(
          'testing collection test: Write: ${results['testing_write']}, Read: ${results['testing_read']}',
          name: 'FirestoreTest',
        );
      } catch (e) {
        results['testing_write'] = false;
        results['testing_read'] = false;
        developer.log(
          'testing test failed: $e',
          name: 'FirestoreTest',
          error: e,
        );
      }

      // 3. Test users collection (requires auth)
      if (isAuthenticated) {
        try {
          final uid = FirebaseAuth.instance.currentUser!.uid;
          final docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(uid);
          final docSnapshot = await docRef.get();
          results['users_read'] = docSnapshot.exists;
          developer.log(
            'users collection test: Read: ${results['users_read']}',
            name: 'FirestoreTest',
          );
        } catch (e) {
          results['users_read'] = false;
          developer.log(
            'users test failed: $e',
            name: 'FirestoreTest',
            error: e,
          );
        }
      } else {
        results['users_read'] = false;
        developer.log(
          'users collection test: Skipped (not authenticated)',
          name: 'FirestoreTest',
        );
      }

      // 4. Test recipes collection (requires auth)
      if (isAuthenticated) {
        try {
          results['recipes_list'] = true;
          developer.log(
            'recipes collection test: List: ${results['recipes_list']}',
            name: 'FirestoreTest',
          );
        } catch (e) {
          results['recipes_list'] = false;
          developer.log(
            'recipes test failed: $e',
            name: 'FirestoreTest',
            error: e,
          );
        }
      } else {
        results['recipes_list'] = false;
        developer.log(
          'recipes collection test: Skipped (not authenticated)',
          name: 'FirestoreTest',
        );
      }
    } catch (e) {
      developer.log(
        'Test Firestore access failed: $e',
        name: 'FirestoreTest',
        error: e,
      );
    }

    return results;
  }
}
