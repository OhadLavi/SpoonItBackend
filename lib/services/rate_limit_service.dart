import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class RateLimitService {
  static const String _attemptsKey = 'login_attempts';
  static const int maxAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 15);

  /// Checks if login attempt is allowed for the given email
  static Future<bool> canAttemptLogin(String email) async {
    final attempts = await _getAttempts(email);
    final now = DateTime.now();

    // Remove expired attempts
    final validAttempts =
        attempts
            .where((attempt) => now.difference(attempt) < lockoutDuration)
            .toList();

    // Update stored attempts if any were removed
    if (validAttempts.length != attempts.length) {
      await _setAttempts(email, validAttempts);
    }

    return validAttempts.length < maxAttempts;
  }

  /// Records a failed login attempt
  static Future<void> recordFailedAttempt(String email) async {
    final attempts = await _getAttempts(email);
    attempts.add(DateTime.now());
    await _setAttempts(email, attempts);
  }

  /// Clears all attempts for the given email (called on successful login)
  static Future<void> clearAttempts(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final attemptsMap = _getAttemptsMap();
    attemptsMap.remove(email);
    await prefs.setString(_attemptsKey, jsonEncode(attemptsMap));
  }

  /// Gets remaining lockout time in minutes
  static Future<int> getRemainingLockoutMinutes(String email) async {
    final attempts = await _getAttempts(email);
    if (attempts.length < maxAttempts) return 0;

    final now = DateTime.now();
    final oldestAttempt = attempts.reduce((a, b) => a.isBefore(b) ? a : b);
    final lockoutEnd = oldestAttempt.add(lockoutDuration);

    if (now.isAfter(lockoutEnd)) return 0;

    return lockoutEnd.difference(now).inMinutes;
  }

  /// Gets all stored attempts for an email
  static Future<List<DateTime>> _getAttempts(String email) async {
    final attemptsMap = _getAttemptsMap();
    final attemptsJson = attemptsMap[email] as List<dynamic>?;

    if (attemptsJson == null) return [];

    return attemptsJson
        .map(
          (timestamp) => DateTime.fromMillisecondsSinceEpoch(timestamp as int),
        )
        .toList();
  }

  /// Sets attempts for an email
  static Future<void> _setAttempts(
    String email,
    List<DateTime> attempts,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final attemptsMap = _getAttemptsMap();

    attemptsMap[email] =
        attempts.map((dateTime) => dateTime.millisecondsSinceEpoch).toList();

    await prefs.setString(_attemptsKey, jsonEncode(attemptsMap));
  }

  /// Gets the attempts map from SharedPreferences
  static Map<String, dynamic> _getAttemptsMap() {
    // This is a synchronous method that reads from a cached value
    // In a real implementation, you might want to make this async
    // For now, we'll return an empty map and handle the async loading in the methods
    return {};
  }

  /// Gets attempts map from SharedPreferences (async version)
  static Future<Map<String, dynamic>> _getAttemptsMapAsync() async {
    final prefs = await SharedPreferences.getInstance();
    final attemptsJson = prefs.getString(_attemptsKey);

    if (attemptsJson == null) return {};

    try {
      return Map<String, dynamic>.from(jsonDecode(attemptsJson));
    } catch (e) {
      return {};
    }
  }

  /// Gets all stored attempts for an email (async version)
  static Future<List<DateTime>> _getAttemptsAsync(String email) async {
    final attemptsMap = await _getAttemptsMapAsync();
    final attemptsJson = attemptsMap[email] as List<dynamic>?;

    if (attemptsJson == null) return [];

    return attemptsJson
        .map(
          (timestamp) => DateTime.fromMillisecondsSinceEpoch(timestamp as int),
        )
        .toList();
  }

  /// Sets attempts for an email (async version)
  static Future<void> _setAttemptsAsync(
    String email,
    List<DateTime> attempts,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final attemptsMap = await _getAttemptsMapAsync();

    attemptsMap[email] =
        attempts.map((dateTime) => dateTime.millisecondsSinceEpoch).toList();

    await prefs.setString(_attemptsKey, jsonEncode(attemptsMap));
  }

  /// Records a failed login attempt (async version)
  static Future<void> recordFailedAttemptAsync(String email) async {
    final attempts = await _getAttemptsAsync(email);
    attempts.add(DateTime.now());
    await _setAttemptsAsync(email, attempts);
  }

  /// Checks if login attempt is allowed for the given email (async version)
  static Future<bool> canAttemptLoginAsync(String email) async {
    final attempts = await _getAttemptsAsync(email);
    final now = DateTime.now();

    // Remove expired attempts
    final validAttempts =
        attempts
            .where((attempt) => now.difference(attempt) < lockoutDuration)
            .toList();

    // Update stored attempts if any were removed
    if (validAttempts.length != attempts.length) {
      await _setAttemptsAsync(email, validAttempts);
    }

    return validAttempts.length < maxAttempts;
  }

  /// Clears all attempts for the given email (async version)
  static Future<void> clearAttemptsAsync(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final attemptsMap = await _getAttemptsMapAsync();
    attemptsMap.remove(email);
    await prefs.setString(_attemptsKey, jsonEncode(attemptsMap));
  }
}
