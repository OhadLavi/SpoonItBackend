import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;

enum AppLanguage { hebrew, english }

class SettingsState {
  final AppLanguage language;
  final ThemeMode themeMode;

  SettingsState({required this.language, required this.themeMode});

  SettingsState copyWith({AppLanguage? language, ThemeMode? themeMode}) {
    return SettingsState(
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    // Initialize with default values first
    state = SettingsState(
      language: AppLanguage.hebrew,
      themeMode: ThemeMode.light,
    );
    // Load preferences asynchronously
    _loadPreferences();
    return state;
  }

  static const String _languageKey = 'app_language';
  static const String _themeModeKey = 'theme_mode';

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load language preference, default to Hebrew if not set
      final savedLanguage = prefs.getString(_languageKey);
      final language =
          savedLanguage != null
              ? AppLanguage.values.firstWhere(
                (l) => l.toString() == savedLanguage,
                orElse: () => AppLanguage.hebrew,
              )
              : AppLanguage.hebrew;

      // Load theme mode preference, default to dark if not set
      final themeModeValue =
          prefs.getInt(_themeModeKey) ?? ThemeMode.light.index;

      state = SettingsState(
        language: language,
        themeMode: ThemeMode.values[themeModeValue],
      );
    } catch (e) {
      // If there's an error loading preferences, keep the default state
      developer.log('Error loading preferences: $e', name: 'SettingsNotifier');
    }
  }

  Future<void> toggleLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final newLanguage =
          state.language == AppLanguage.hebrew
              ? AppLanguage.english
              : AppLanguage.hebrew;

      // Save the full language enum value as a string
      await prefs.setString(_languageKey, newLanguage.toString());
      state = state.copyWith(language: newLanguage);
    } catch (e) {
      developer.log(
        'Error saving language preference: $e',
        name: 'SettingsNotifier',
      );
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
    state = state.copyWith(themeMode: mode);
  }

  bool get isHebrew => state.language == AppLanguage.hebrew;
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  () => SettingsNotifier(),
);

// Convenience providers to access specific settings
final languageProvider = Provider<AppLanguage>((ref) {
  return ref.watch(settingsProvider).language;
});

final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(settingsProvider).themeMode;
});
