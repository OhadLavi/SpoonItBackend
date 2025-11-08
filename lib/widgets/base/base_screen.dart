import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/widgets/app_bottom_nav.dart';
import 'package:spoonit/widgets/feedback/app_loading_indicator.dart';
import 'package:spoonit/widgets/feedback/app_error_container.dart';
import 'package:spoonit/providers/service_providers.dart';
import 'package:spoonit/services/error_handler_service.dart';

/// Base screen architecture for consistent patterns across all screens
///
/// This provides:
/// - Consistent error handling
/// - Standardized loading states
/// - Proper service access patterns
/// - Common UI patterns

abstract class BaseScreen extends ConsumerStatefulWidget {
  const BaseScreen({super.key});

  /// Override to provide custom bottom navigation index
  int get bottomNavIndex => -1;

  /// Override to provide custom background color
  Color get backgroundColor => AppTheme.backgroundColor;

  /// Override to provide custom app bar
  PreferredSizeWidget? get appBar => null;

  /// Override to provide custom floating action button
  Widget? get floatingActionButton => null;
}

abstract class BaseScreenState<T extends BaseScreen> extends ConsumerState<T> {
  bool _isLoading = false;
  String? _errorMessage;

  /// Current loading state
  bool get isLoading => _isLoading;

  /// Current error message
  String? get errorMessage => _errorMessage;

  /// Set loading state
  void setLoading(bool loading) {
    if (mounted) {
      setState(() => _isLoading = loading);
    }
  }

  /// Set error message
  void setError(String? error) {
    if (mounted) {
      setState(() => _errorMessage = error);
    }
  }

  /// Clear error message
  void clearError() {
    if (mounted) {
      setState(() => _errorMessage = null);
    }
  }

  /// Execute service call with consistent error handling
  Future<ServiceResult<R>> executeService<R>(
    Future<R> Function() serviceCall,
  ) async {
    setLoading(true);
    clearError();

    try {
      final result = await serviceCall();
      setLoading(false);
      return ServiceResult.success(result);
    } catch (e) {
      setLoading(false);
      final errorMessage = ErrorHandlerService.handleApiError(e, ref);
      setError(errorMessage.userMessage);
      return ServiceResult.error(errorMessage.userMessage);
    }
  }

  /// Handle service result with consistent patterns
  void handleServiceResult<R>(
    ServiceResult<R> result,
    void Function(R data) onSuccess, {
    void Function(String error)? onError,
  }) {
    result.fold(
      (error) {
        setError(error);
        onError?.call(error);
      },
      (data) {
        clearError();
        onSuccess(data);
      },
    );
  }

  /// Build error display widget
  Widget buildErrorDisplay() {
    if (_errorMessage == null) return const SizedBox.shrink();

    return AppErrorContainer(message: _errorMessage!, onDismiss: clearError);
  }

  /// Build loading display widget
  Widget buildLoadingDisplay() {
    if (!_isLoading) return const SizedBox.shrink();

    return const Center(child: AppLoadingIndicator());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.backgroundColor,
      appBar: widget.appBar,
      body: buildBody(context),
      bottomNavigationBar:
          widget.bottomNavIndex >= 0
              ? AppBottomNav(currentIndex: widget.bottomNavIndex)
              : null,
      floatingActionButton: widget.floatingActionButton,
    );
  }

  /// Override to provide screen-specific body content
  Widget buildBody(BuildContext context);
}

/// Base screen for screens that don't need state management
abstract class BaseStatelessScreen extends ConsumerWidget {
  const BaseStatelessScreen({super.key});

  /// Override to provide custom bottom navigation index
  int get bottomNavIndex => -1;

  /// Override to provide custom background color
  Color get backgroundColor => AppTheme.backgroundColor;

  /// Override to provide custom app bar
  PreferredSizeWidget? get appBar => null;

  /// Override to provide custom floating action button
  Widget? get floatingActionButton => null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: appBar,
      body: buildBody(context, ref),
      bottomNavigationBar:
          bottomNavIndex >= 0
              ? AppBottomNav(currentIndex: bottomNavIndex)
              : null,
      floatingActionButton: floatingActionButton,
    );
  }

  /// Override to provide screen-specific body content
  Widget buildBody(BuildContext context, WidgetRef ref);
}
