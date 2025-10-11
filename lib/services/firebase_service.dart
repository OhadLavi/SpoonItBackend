import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:spoonit/firebase_options.dart';

class FirebaseService {
  static bool _isInitialized = false;
  static bool _isOnline = true;
  static StreamSubscription? _connectivitySubscription;

  static Future<void> initializeFirebase() async {
    if (_isInitialized) return;

    try {
      developer.log(
        'Starting Firebase initialization...',
        name: 'FirebaseService',
      );
      developer.log(
        'Project ID: ${DefaultFirebaseOptions.currentPlatform.projectId}',
        name: 'FirebaseService',
      );

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      developer.log(
        'Firebase Core initialized successfully',
        name: 'FirebaseService',
      );

      // Configure Firestore for reliable offline support
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        sslEnabled: true,
        host: 'firestore.googleapis.com',
        ignoreUndefinedProperties: true,
      );

      // Offline persistence is enabled by default in newer versions

      // Add retry logic for initial connection
      int retryCount = 0;
      const maxRetries = 3;

      while (retryCount < maxRetries) {
        try {
          // Check if we can actually connect to Firestore to verify the database exists
          developer.log(
            'Verifying Firestore database connection (attempt ${retryCount + 1})...',
            name: 'FirebaseService',
          );

          // Try access to _health_check collection (public access)
          await FirebaseFirestore.instance
              .collection('_health_check')
              .doc('test')
              .set({
                'timestamp': DateTime.now().toIso8601String(),
                'attempt': retryCount + 1,
              });

          developer.log(
            'Successfully wrote to _health_check collection',
            name: 'FirebaseService',
          );

          // Delete the test document
          await FirebaseFirestore.instance
              .collection('_health_check')
              .doc('test')
              .delete();

          developer.log(
            'Successfully deleted test document from _health_check',
            name: 'FirebaseService',
          );

          break; // Success, exit retry loop
        } catch (e) {
          retryCount++;
          developer.log(
            'Connection attempt $retryCount failed: $e',
            name: 'FirebaseService',
            error: e,
          );

          if (retryCount == maxRetries) {
            developer.log(
              'Max retry attempts reached. Connection failed.',
              name: 'FirebaseService',
            );
            rethrow;
          }

          // Wait before retrying
          await Future.delayed(Duration(seconds: 2 * retryCount));
        }
      }

      // Initialize connectivity monitoring
      await _setupConnectivityMonitoring();

      // Add Firestore error logging
      setupFirestoreErrorLogging();

      _isInitialized = true;
    } catch (e, stackTrace) {
      developer.log(
        'Error initializing Firebase: $e',
        name: 'FirebaseService',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static Future<void> _setupConnectivityMonitoring() async {
    try {
      // Check initial connectivity state
      final connectivityResult = await Connectivity().checkConnectivity();
      _updateConnectionState(connectivityResult);

      // Listen for connectivity changes
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
        (List<ConnectivityResult> results) {
          _updateConnectionState(results);
        },
        onError: (error) {
          developer.log(
            'Connectivity monitoring error: $error',
            name: 'FirebaseService',
            error: error,
          );
        },
      );

      developer.log(
        'Connectivity monitoring initialized',
        name: 'FirebaseService',
      );
    } catch (e) {
      developer.log(
        'Error setting up connectivity monitoring: $e',
        name: 'FirebaseService',
        error: e,
      );
    }
  }

  static void _updateConnectionState(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    _isOnline = !results.contains(ConnectivityResult.none);

    if (wasOnline != _isOnline) {
      developer.log(
        'Connection state changed: ${_isOnline ? "ONLINE" : "OFFLINE"}',
        name: 'FirebaseService',
      );

      if (_isOnline) {
        // Try to reconnect Firestore by disabling and re-enabling the network
        _enableFirestoreNetwork();
      } else {
        _disableFirestoreNetwork();
      }
    }
  }

  static Future<void> _enableFirestoreNetwork() async {
    try {
      // Enable Firestore network operations
      await FirebaseFirestore.instance.enableNetwork();
      developer.log('Firestore network enabled', name: 'FirebaseService');
    } catch (e) {
      developer.log(
        'Error enabling Firestore network: $e',
        name: 'FirebaseService',
        error: e,
      );
    }
  }

  static Future<void> _disableFirestoreNetwork() async {
    try {
      // Disable Firestore network operations to force offline mode
      await FirebaseFirestore.instance.disableNetwork();
      developer.log('Firestore network disabled', name: 'FirebaseService');
    } catch (e) {
      developer.log(
        'Error disabling Firestore network: $e',
        name: 'FirebaseService',
        error: e,
      );
    }
  }

  static void setupFirestoreErrorLogging() {
    // Listen for errors on specific collections
    FirebaseFirestore.instance.collection('recipes').snapshots().handleError((
      error,
    ) {
      developer.log(
        'Error in recipes collection: $error',
        name: 'FirestoreError',
        error: error,
      );
    });

    FirebaseFirestore.instance.collection('users').snapshots().handleError((
      error,
    ) {
      developer.log(
        'Error in users collection: $error',
        name: 'FirestoreError',
        error: error,
      );
    });

    developer.log(
      'Firestore error logging configured',
      name: 'FirebaseService',
    );
  }

  static void logFirestoreOperation(
    String operation,
    String collection,
    String? docId, [
    dynamic data,
  ]) {
    String message = 'Firestore $operation on $collection';
    if (docId != null) message += ' (ID: $docId)';
    if (data != null) {
      final dataStr = data.toString();
      message +=
          ': ${dataStr.length > 100 ? '${dataStr.substring(0, 100)}...' : dataStr}';
    }

    developer.log(message, name: 'FirestoreOperation');
  }

  static bool get isOnline => _isOnline;

  static void dispose() {
    _connectivitySubscription?.cancel();
  }
}
