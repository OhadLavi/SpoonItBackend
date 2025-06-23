import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:recipe_keeper/services/firebase_service.dart';
import 'package:recipe_keeper/utils/app_router.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/widgets/connectivity_widget.dart';
import 'package:recipe_keeper/firebase_options.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:recipe_keeper/providers/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase Core FIRST
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    developer.log('Firebase Core initialized in main()', name: 'Main');

    // Configure Firestore Settings and Persistence BEFORE first use
    try {
      // Get the instance
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      // Set the settings on the instance
      firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        sslEnabled: true,
        ignoreUndefinedProperties: true,
      );
      developer.log('Firestore settings applied', name: 'Main');
      // Persistence is enabled via the settings, no separate call needed
    } catch (e, stack) {
      developer.log(
        'Error configuring Firestore settings/persistence: $e',
        name: 'Main',
        error: e,
        stackTrace: stack,
      );
    }

    // Now run the app
    runApp(const ProviderScope(child: RecipeKeeperApp()));

    // Initialize other services and run diagnostics AFTER runApp
    // Diagnostics can sometimes interfere with initial web load, comment out for now
    /*
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // await FirebaseService.initializeFirebase(); // This might be redundant now
      // developer.log('Firebase service initialized post-frame', name: 'Main');
      await _runDiagnostics(); 
    });
    */
  } catch (e, stackTrace) {
    developer.log(
      'Firebase initialization error in main(): $e',
      name: 'Main',
      error: e,
      stackTrace: stackTrace,
    );
    // Optionally run a fallback app if Firebase init fails critically
    runApp(const ProviderScope(child: RecipeKeeperApp())); // Still run app
  }
}

class RecipeKeeperApp extends ConsumerWidget {
  const RecipeKeeperApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Register a callback to dispose Firebase when app is terminated
    if (!kIsWeb) {
      // Skip in web to avoid DOM issues
      WidgetsBinding.instance.addObserver(_AppLifecycleObserver());
    }

    final settings = ref.watch(settingsProvider);
    final isHebrew = settings.language == AppLanguage.hebrew;
    final themeMode = settings.themeMode;

    return MaterialApp.router(
      title: 'Recipe Keeper',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: AppRouter.router,
      debugShowCheckedModeBanner: false,
      // Add localization support
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('he', 'IL'), // Hebrew
        Locale('en', 'US'), // English
      ],
      locale: isHebrew ? const Locale('he', 'IL') : const Locale('en', 'US'),
      builder: (context, child) {
        // Wrap the entire app with the connectivity widget
        return Directionality(
          textDirection: isHebrew ? TextDirection.rtl : TextDirection.ltr,
          child: ConnectivityWidget(child: child ?? const SizedBox()),
        );
      },
    );
  }
}

/// Observer to handle app lifecycle events
class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // App is being terminated, clean up resources
      FirebaseService.dispose();
    }
  }
}
