import 'package:flutter/foundation.dart' show kDebugMode;

// Configuration for API endpoints and environment variables
class EnvConfig {
  // Production backend URL (Google Cloud Run)
  static const String _productionApiUrl = 'https://spoonitbackend-764665084777.europe-west1.run.app';
  
  // Local development URL
  static const String _developmentApiUrl = 'http://localhost:8001';
  
  /// Returns the API base URL based on build mode
  /// - Debug mode: Uses localhost for local development
  /// - Release mode: Uses production Cloud Run URL
  static String get apiBaseUrl {
    if (kDebugMode) {
      return _developmentApiUrl;
    }
    return _productionApiUrl;
  }
  
  /// Check if running in production mode
  static bool get isProduction => !kDebugMode;

  // Add other environment variables as needed
  // static String get firebaseProjectId => '';
}
