import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';

enum SecurityEventType {
  loginAttempt,
  loginSuccess,
  loginFailure,
  registrationAttempt,
  registrationSuccess,
  registrationFailure,
  passwordChange,
  passwordReset,
  accountDeletion,
  profileUpdate,
  suspiciousActivity,
  rateLimitExceeded,
}

class AuditLogger {
  static const String _logPrefix = '[SECURITY]';

  /// Logs a security event with timestamp and metadata
  static void logSecurityEvent(
    SecurityEventType eventType,
    Map<String, dynamic> metadata,
  ) {
    final timestamp = DateTime.now().toIso8601String();
    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

    final logData = {
      'timestamp': timestamp,
      'event': eventType.name,
      'userId': userId,
      'metadata': metadata,
    };

    developer.log(
      '$_logPrefix ${eventType.name.toUpperCase()}',
      name: 'SecurityAudit',
      error: logData,
    );
  }

  /// Logs login attempt
  static void logLoginAttempt(String email, String method) {
    logSecurityEvent(SecurityEventType.loginAttempt, {
      'email': email,
      'method': method,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Logs successful login
  static void logLoginSuccess(String email, String method) {
    logSecurityEvent(SecurityEventType.loginSuccess, {
      'email': email,
      'method': method,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Logs failed login
  static void logLoginFailure(String email, String method, String reason) {
    logSecurityEvent(SecurityEventType.loginFailure, {
      'email': email,
      'method': method,
      'reason': reason,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Logs registration attempt
  static void logRegistrationAttempt(String email, String method) {
    logSecurityEvent(SecurityEventType.registrationAttempt, {
      'email': email,
      'method': method,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Logs successful registration
  static void logRegistrationSuccess(String email, String method) {
    logSecurityEvent(SecurityEventType.registrationSuccess, {
      'email': email,
      'method': method,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Logs failed registration
  static void logRegistrationFailure(
    String email,
    String method,
    String reason,
  ) {
    logSecurityEvent(SecurityEventType.registrationFailure, {
      'email': email,
      'method': method,
      'reason': reason,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Logs password change
  static void logPasswordChange(String userId) {
    logSecurityEvent(SecurityEventType.passwordChange, {
      'userId': userId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Logs password reset request
  static void logPasswordReset(String email) {
    logSecurityEvent(SecurityEventType.passwordReset, {
      'email': email,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Logs account deletion
  static void logAccountDeletion(String userId, String email) {
    logSecurityEvent(SecurityEventType.accountDeletion, {
      'userId': userId,
      'email': email,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Logs profile update
  static void logProfileUpdate(String userId, List<String> updatedFields) {
    logSecurityEvent(SecurityEventType.profileUpdate, {
      'userId': userId,
      'updatedFields': updatedFields,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Logs suspicious activity
  static void logSuspiciousActivity(
    String userId,
    String activity,
    Map<String, dynamic> details,
  ) {
    logSecurityEvent(SecurityEventType.suspiciousActivity, {
      'userId': userId,
      'activity': activity,
      'details': details,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Logs rate limit exceeded
  static void logRateLimitExceeded(String email, int attemptCount) {
    logSecurityEvent(SecurityEventType.rateLimitExceeded, {
      'email': email,
      'attemptCount': attemptCount,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Logs generic security event
  static void logGenericEvent(String eventName, Map<String, dynamic> metadata) {
    final timestamp = DateTime.now().toIso8601String();
    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

    final logData = {
      'timestamp': timestamp,
      'event': eventName,
      'userId': userId,
      'metadata': metadata,
    };

    developer.log(
      '$_logPrefix ${eventName.toUpperCase()}',
      name: 'SecurityAudit',
      error: logData,
    );
  }

  /// Formats log entry for display
  static String formatLogEntry(Map<String, dynamic> logData) {
    final timestamp = logData['timestamp'] ?? 'Unknown';
    final event = logData['event'] ?? 'Unknown';
    final userId = logData['userId'] ?? 'Unknown';
    final metadata = logData['metadata'] ?? {};

    return '[$timestamp] $event - User: $userId - Data: $metadata';
  }

  /// Gets all security events (for debugging purposes)
  static List<String> getAllSecurityEvents() {
    // This would typically read from a log file or database
    // For now, return empty list as we're using developer.log
    return [];
  }

  /// Clears all security events (for testing purposes)
  static void clearAllEvents() {
    // This would typically clear log files or database entries
    // For now, do nothing as we're using developer.log
  }
}
