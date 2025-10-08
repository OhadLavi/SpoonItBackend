// lib/main.dart
import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:recipe_keeper/firebase_options.dart';
import 'package:recipe_keeper/utils/app_router.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/widgets/connectivity_widget.dart';
import 'package:recipe_keeper/providers/settings_provider.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/services/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global error handlers (avoid PII in production logs)
  FlutterError.onError = (FlutterErrorDetails details) {
    developer.log(
      'FlutterError',
      name: 'Main',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  runZonedGuarded(
    () async {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      developer.log('Firebase initialized', name: 'Main');

      // Firestore settings (avoid unlimited cache)
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 100 * 1024 * 1024, // 100MB
        ignoreUndefinedProperties: true,
        sslEnabled: true,
      );

      runApp(const ProviderScope(child: RecipeKeeperApp()));
    },
    (error, stack) {
      developer.log(
        'Uncaught zone error',
        name: 'Main',
        error: error,
        stackTrace: stack,
      );
      runApp(const ProviderScope(child: RecipeKeeperApp()));
    },
  );
}

class RecipeKeeperApp extends ConsumerStatefulWidget {
  const RecipeKeeperApp({super.key});

  @override
  ConsumerState<RecipeKeeperApp> createState() => _RecipeKeeperAppState();
}

class _RecipeKeeperAppState extends ConsumerState<RecipeKeeperApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // App is being terminated, clean up resources
      FirebaseService.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Touching auth provider ensures it’s initialized
    final authState = ref.watch(authProvider);
    if (kDebugMode) {
      developer.log('Auth status=${authState.status}', name: 'Main');
    }

    final settings = ref.watch(settingsProvider);
    final isHebrew = settings.language == AppLanguage.hebrew;
    final themeMode = settings.themeMode;

    return MaterialApp.router(
      title: 'SpoonIt',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: AppRouter.router,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('he', 'IL'), Locale('en', 'US')],
      locale: isHebrew ? const Locale('he', 'IL') : const Locale('en', 'US'),
      builder: (context, child) {
        // MaterialApp provides Directionality from locale
        return ConnectivityWidget(child: child ?? const SizedBox());
      },
    );
  }
}
