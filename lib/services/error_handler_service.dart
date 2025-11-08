import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoonit/utils/translations.dart';

/// Standardized error object with user-friendly message and technical details
class AppError {
  final String userMessage;
  final String? technicalMessage;
  final String? errorCode;
  final ErrorSeverity severity;
  final DateTime timestamp;

  AppError({
    required this.userMessage,
    this.technicalMessage,
    this.errorCode,
    this.severity = ErrorSeverity.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => userMessage;
}

enum ErrorSeverity { info, warning, error, critical }

/// Centralized error handling service
class ErrorHandlerService {
  static const String _logName = 'ErrorHandlerService';

  /// Handle API errors and convert them to user-friendly messages
  static AppError handleApiError(dynamic error, WidgetRef ref) {
    final errorString = error.toString().toLowerCase();

    // Network errors
    if (errorString.contains('socketexception') ||
        errorString.contains('network') ||
        errorString.contains('connection')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'network_error'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.warning,
      );
    }

    // Timeout errors
    if (errorString.contains('timeout')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'timeout_error'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.warning,
      );
    }

    // Server errors (5xx)
    if (errorString.contains('500') ||
        errorString.contains('502') ||
        errorString.contains('503')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'server_error'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.error,
      );
    }

    // Client errors (4xx)
    if (errorString.contains('400') ||
        errorString.contains('401') ||
        errorString.contains('403') ||
        errorString.contains('404')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'client_error'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.error,
      );
    }

    // Generic API error
    return AppError(
      userMessage: AppTranslations.getText(ref, 'api_error'),
      technicalMessage: error.toString(),
      severity: ErrorSeverity.error,
    );
  }

  /// Handle authentication errors specifically
  static AppError handleAuthError(dynamic error, WidgetRef ref) {
    // Handle Firebase Auth exceptions properly
    if (error is FirebaseAuthException) {
      return _handleFirebaseAuthException(error, ref);
    }

    // Fallback to string matching for other error types
    final errorString = error.toString().toLowerCase();

    // Invalid credentials
    if (errorString.contains('invalid') &&
        (errorString.contains('credential') ||
            errorString.contains('password'))) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'invalid_credentials'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.error,
        errorCode: 'invalid-credential',
      );
    }

    // User not found
    if (errorString.contains('user-not-found') ||
        errorString.contains('user not found')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'user_not_found'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.error,
        errorCode: 'user-not-found',
      );
    }

    // Email already in use
    if (errorString.contains('email-already-in-use') ||
        errorString.contains('email already in use')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'email_already_in_use'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.error,
        errorCode: 'email-already-in-use',
      );
    }

    // Weak password
    if (errorString.contains('weak-password') ||
        errorString.contains('weak password')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'weak_password'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.warning,
        errorCode: 'weak-password',
      );
    }

    // Too many requests
    if (errorString.contains('too-many-requests') ||
        errorString.contains('too many requests')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'too_many_requests'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.warning,
        errorCode: 'too-many-requests',
      );
    }

    // Account disabled
    if (errorString.contains('user-disabled') ||
        errorString.contains('user disabled')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'account_disabled'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.error,
        errorCode: 'user-disabled',
      );
    }

    // Network errors in auth context
    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('socketexception')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'network_error'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.warning,
        errorCode: 'network-error',
      );
    }

    // Generic auth error
    return AppError(
      userMessage: AppTranslations.getText(ref, 'auth_error'),
      technicalMessage: error.toString(),
      severity: ErrorSeverity.error,
      errorCode: 'unknown-auth-error',
    );
  }

  /// Handle Firebase Auth exceptions with specific error codes
  static AppError _handleFirebaseAuthException(
    FirebaseAuthException error,
    WidgetRef ref,
  ) {
    switch (error.code) {
      case 'user-not-found':
        return AppError(
          userMessage: AppTranslations.getText(ref, 'user_not_found'),
          technicalMessage: error.message ?? error.toString(),
          errorCode: error.code,
          severity: ErrorSeverity.error,
        );

      case 'wrong-password':
      case 'invalid-credential':
        return AppError(
          userMessage: AppTranslations.getText(ref, 'invalid_credentials'),
          technicalMessage: error.message ?? error.toString(),
          errorCode: error.code,
          severity: ErrorSeverity.error,
        );

      case 'email-already-in-use':
        return AppError(
          userMessage: AppTranslations.getText(ref, 'email_already_in_use'),
          technicalMessage: error.message ?? error.toString(),
          errorCode: error.code,
          severity: ErrorSeverity.error,
        );

      case 'weak-password':
        return AppError(
          userMessage: AppTranslations.getText(ref, 'weak_password'),
          technicalMessage: error.message ?? error.toString(),
          errorCode: error.code,
          severity: ErrorSeverity.warning,
        );

      case 'too-many-requests':
        return AppError(
          userMessage: AppTranslations.getText(ref, 'too_many_requests'),
          technicalMessage: error.message ?? error.toString(),
          errorCode: error.code,
          severity: ErrorSeverity.warning,
        );

      case 'user-disabled':
        return AppError(
          userMessage: AppTranslations.getText(ref, 'account_disabled'),
          technicalMessage: error.message ?? error.toString(),
          errorCode: error.code,
          severity: ErrorSeverity.error,
        );

      case 'invalid-email':
        return AppError(
          userMessage: AppTranslations.getText(ref, 'invalid_email'),
          technicalMessage: error.message ?? error.toString(),
          errorCode: error.code,
          severity: ErrorSeverity.warning,
        );

      case 'operation-not-allowed':
        return AppError(
          userMessage: AppTranslations.getText(ref, 'operation_not_allowed'),
          technicalMessage: error.message ?? error.toString(),
          errorCode: error.code,
          severity: ErrorSeverity.error,
        );

      case 'requires-recent-login':
        return AppError(
          userMessage: AppTranslations.getText(ref, 'requires_recent_login'),
          technicalMessage: error.message ?? error.toString(),
          errorCode: error.code,
          severity: ErrorSeverity.warning,
        );

      case 'network-request-failed':
      case 'network_error':
        return AppError(
          userMessage: AppTranslations.getText(ref, 'network_error'),
          technicalMessage: error.message ?? error.toString(),
          errorCode: error.code,
          severity: ErrorSeverity.warning,
        );

      case 'quota-exceeded':
        return AppError(
          userMessage: AppTranslations.getText(ref, 'quota_exceeded'),
          technicalMessage: error.message ?? error.toString(),
          errorCode: error.code,
          severity: ErrorSeverity.error,
        );

      case 'app-not-authorized':
      case 'api-key-not-valid':
        return AppError(
          userMessage: AppTranslations.getText(ref, 'auth_config_error'),
          technicalMessage: error.message ?? error.toString(),
          errorCode: error.code,
          severity: ErrorSeverity.error,
        );

      default:
        // For unknown Firebase Auth errors, provide a generic message
        return AppError(
          userMessage: AppTranslations.getText(ref, 'auth_error'),
          technicalMessage: error.message ?? error.toString(),
          errorCode: error.code,
          severity: ErrorSeverity.error,
        );
    }
  }

  /// Handle form validation errors
  static AppError handleValidationError(dynamic error, WidgetRef ref) {
    final errorString = error.toString().toLowerCase();

    // Required field
    if (errorString.contains('required') || errorString.contains('empty')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'field_required'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.warning,
      );
    }

    // Invalid email
    if (errorString.contains('email') && errorString.contains('invalid')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'invalid_email'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.warning,
      );
    }

    // Password too short
    if (errorString.contains('password') &&
        (errorString.contains('short') || errorString.contains('length'))) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'password_too_short'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.warning,
      );
    }

    // Generic validation error
    return AppError(
      userMessage: AppTranslations.getText(ref, 'validation_error'),
      technicalMessage: error.toString(),
      severity: ErrorSeverity.warning,
    );
  }

  /// Handle file operation errors
  static AppError handleFileError(dynamic error, WidgetRef ref) {
    final errorString = error.toString().toLowerCase();

    // File not found
    if (errorString.contains('file not found') ||
        errorString.contains('no such file')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'file_not_found'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.error,
      );
    }

    // Permission denied
    if (errorString.contains('permission') ||
        errorString.contains('access denied')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'permission_denied'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.error,
      );
    }

    // File too large
    if (errorString.contains('too large') ||
        errorString.contains('size limit')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'file_too_large'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.warning,
      );
    }

    // Generic file error
    return AppError(
      userMessage: AppTranslations.getText(ref, 'file_error'),
      technicalMessage: error.toString(),
      severity: ErrorSeverity.error,
    );
  }

  /// Handle database/storage errors
  static AppError handleStorageError(dynamic error, WidgetRef ref) {
    final errorString = error.toString().toLowerCase();

    // Permission denied
    if (errorString.contains('permission') ||
        errorString.contains('access denied')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'storage_permission_denied'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.error,
      );
    }

    // Quota exceeded
    if (errorString.contains('quota') || errorString.contains('storage full')) {
      return AppError(
        userMessage: AppTranslations.getText(ref, 'storage_quota_exceeded'),
        technicalMessage: error.toString(),
        severity: ErrorSeverity.error,
      );
    }

    // Generic storage error
    return AppError(
      userMessage: AppTranslations.getText(ref, 'storage_error'),
      technicalMessage: error.toString(),
      severity: ErrorSeverity.error,
    );
  }

  /// Generic error handler for unknown error types
  static AppError handleGenericError(dynamic error, WidgetRef ref) {
    return AppError(
      userMessage: AppTranslations.getText(ref, 'unknown_error'),
      technicalMessage: error.toString(),
      severity: ErrorSeverity.error,
    );
  }

  /// Centralized error logging
  static void logError(
    dynamic error,
    StackTrace? stackTrace, {
    String? context,
    Map<String, dynamic>? additionalData,
  }) {
    final logMessage = 'Error${context != null ? ' in $context' : ''}: $error';

    developer.log(
      logMessage,
      name: _logName,
      error: error,
      stackTrace: stackTrace,
    );

    // Log additional data if provided
    if (additionalData != null && additionalData.isNotEmpty) {
      developer.log('Additional data: $additionalData', name: _logName);
    }
  }

  /// Log and handle error in one call
  static AppError logAndHandleError(
    dynamic error,
    WidgetRef ref, {
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? additionalData,
    ErrorType type = ErrorType.generic,
  }) {
    // Log the error
    logError(
      error,
      stackTrace,
      context: context,
      additionalData: additionalData,
    );

    // Handle based on type
    switch (type) {
      case ErrorType.api:
        return handleApiError(error, ref);
      case ErrorType.auth:
        return handleAuthError(error, ref);
      case ErrorType.validation:
        return handleValidationError(error, ref);
      case ErrorType.file:
        return handleFileError(error, ref);
      case ErrorType.storage:
        return handleStorageError(error, ref);
      case ErrorType.generic:
        return handleGenericError(error, ref);
    }
  }
}

enum ErrorType { api, auth, validation, file, storage, generic }
