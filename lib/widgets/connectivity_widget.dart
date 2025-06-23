import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:recipe_keeper/services/firebase_service.dart';

final connectivityProvider = StreamProvider<bool>((ref) {
  final controller = StreamController<bool>();

  // Initial value
  controller.add(FirebaseService.isOnline);

  // Set up a timer to check connectivity status periodically
  Timer? timer;

  // Delay the timer initialization to avoid DOM issues on web
  Future.delayed(const Duration(milliseconds: 500), () {
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      try {
        controller.add(FirebaseService.isOnline);
      } catch (e) {
        // Ignore errors if the controller is closed
      }
    });
  });

  // Clean up when the provider is disposed
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });

  return controller.stream;
});

class ConnectivityWidget extends ConsumerWidget {
  final Widget child;
  final bool showBanner;

  const ConnectivityWidget({
    super.key,
    required this.child,
    this.showBanner = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // On web, we need to be extra careful with stream-based widgets
    if (kIsWeb) {
      // Use a simpler approach for web to avoid DOM issues
      return Stack(
        children: [
          child,
          if (!FirebaseService.isOnline && showBanner)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildOfflineBanner(context),
            ),
        ],
      );
    }

    // For mobile, use the reactive approach
    final connectivity = ref.watch(connectivityProvider);

    return connectivity.when(
      data: (isOnline) {
        return Stack(
          children: [
            child,
            if (!isOnline && showBanner)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildOfflineBanner(context),
              ),
          ],
        );
      },
      loading: () => child,
      error: (_, __) => child,
    );
  }

  Widget _buildOfflineBanner(BuildContext context) {
    return Container(
      color: Colors.red.withOpacity(0.8),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'You are offline. Some features may be limited.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class OfflineAwareBuilder extends ConsumerWidget {
  final Widget Function(BuildContext context, bool isOnline) builder;

  const OfflineAwareBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // On web, use a simpler approach
    if (kIsWeb) {
      return builder(context, FirebaseService.isOnline);
    }

    final connectivity = ref.watch(connectivityProvider);

    return connectivity.when(
      data: (isOnline) => builder(context, isOnline),
      loading: () => builder(context, true), // Assume online while loading
      error: (_, __) => builder(context, true), // Assume online on error
    );
  }
}
