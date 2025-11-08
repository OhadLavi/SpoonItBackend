import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spoonit/providers/auth_provider.dart';
import 'package:spoonit/providers/settings_provider.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/utils/helpers.dart';
import 'package:spoonit/utils/translations.dart';
import 'package:spoonit/widgets/auth_widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:spoonit/utils/responsive_utils.dart';
import 'package:spoonit/utils/language_utils.dart';
import 'package:spoonit/services/rate_limit_service.dart';
import 'package:spoonit/services/audit_logger_service.dart';
import 'package:spoonit/widgets/forms/app_text_field.dart';
import 'package:spoonit/widgets/forms/app_password_field.dart';
import 'package:spoonit/widgets/forms/app_form_container.dart';
import 'package:spoonit/widgets/buttons/app_primary_button.dart';
import 'package:spoonit/widgets/buttons/app_text_button.dart';
import 'package:spoonit/widgets/feedback/app_error_container.dart';
import 'package:spoonit/services/error_handler_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithEmailAndPassword() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();

    // Check rate limiting
    final canAttempt = await RateLimitService.canAttemptLoginAsync(email);
    if (!canAttempt) {
      setState(() {
        _errorMessage = AppTranslations.getText(ref, 'account_locked');
        _isLoading = false;
      });
      AuditLogger.logRateLimitExceeded(email, 5);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(authProvider.notifier)
          .signInWithEmailAndPassword(email, _passwordController.text);

      // Only proceed if we successfully authenticated
      final authState = ref.read(authProvider);
      if (authState.status == AuthStatus.authenticated && authState.user != null) {
        // Clear rate limiting on successful login
        await RateLimitService.clearAttemptsAsync(email);

        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          context.go('/home');
        }
      } else {
        // Authentication failed but no exception was thrown
        if (kDebugMode) {
          developer.log(
            'Login failed: status=${authState.status}, error=${authState.errorMessage}',
            name: 'LoginScreen',
          );
        }
        setState(() {
          _errorMessage = authState.errorMessage ?? 
              ErrorHandlerService.handleAuthError(
                Exception('Authentication failed'),
                ref,
              ).userMessage;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      // Record failed attempt
      await RateLimitService.recordFailedAttemptAsync(email);

      if (kDebugMode) {
        developer.log(
          'Login exception: $e',
          name: 'LoginScreen',
          error: e,
          stackTrace: stackTrace,
        );
      }

      setState(() {
        _errorMessage = ErrorHandlerService.handleAuthError(e, ref).userMessage;
        _isLoading = false;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authProvider.notifier).signInWithGoogle();
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() {
        _errorMessage = ErrorHandlerService.handleAuthError(e, ref).userMessage;
        _isLoading = false;
      });
    }
  }

  Future<void> _signInWithFacebook() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authProvider.notifier).signInWithFacebook();
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() {
        _errorMessage = ErrorHandlerService.handleAuthError(e, ref).userMessage;
        _isLoading = false;
      });
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() {
        _errorMessage = AppTranslations.getText(ref, 'email_required');
      });
      return;
    }

    if (!Helpers.isValidEmail(email)) {
      setState(() {
        _errorMessage = AppTranslations.getText(ref, 'invalid_email');
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authProvider.notifier).resetPassword(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'reset_password_success'),
            ),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final isDark = settings.themeMode == ThemeMode.dark;

    final mainTextColor = isDark ? AppTheme.darkTextColor : AppTheme.textColor;

    final screenWidth = MediaQuery.of(context).size.width;
    // final isWeb = screenWidth > 700;

    // NEW: keep margins on phones, cap width on larger screens
    final double panelWidth = ResponsiveUtils.calculateResponsivePanelWidth(
      context,
    );

    final isHebrew = LanguageUtils.isHebrew(ref);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Background header band
          const AuthHeader(height: 320, showGraphic: false),

          // Icon aligned to the card's left (Hebrew) / right (English)
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: panelWidth, // match the card width
              margin: const EdgeInsets.only(top: 0),
              child: Align(
                alignment: isHebrew ? Alignment.topLeft : Alignment.topRight,
                child: SvgPicture.asset(
                  'assets/images/login.svg',
                  width: 250,
                  height: 250,
                  colorFilter: ColorFilter.mode(
                    isDark ? AppTheme.darkPrimaryColor : AppTheme.textColor,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),

          // Hello text pinned to the top of the card
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: panelWidth,
              margin: const EdgeInsets.only(
                top: 240 - 120,
              ), // 240 = AuthPanel top
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: isHebrew ? Alignment.topRight : Alignment.topLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppTranslations.getText(ref, 'hello'),
                      style: TextStyle(
                        fontFamily: AppTheme.primaryFontFamily,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color:
                            isDark
                                ? AppTheme.darkPrimaryColor
                                : AppTheme.lightAccentColor,
                      ),
                    ),
                    const SizedBox(height: 0),
                    Text(
                      AppTranslations.getText(ref, 'welcome_to_spoonit'),
                      style: TextStyle(
                        fontFamily: AppTheme.primaryFontFamily,
                        fontSize: 18,
                        color:
                            isDark
                                ? AppTheme.darkPrimaryColor
                                : AppTheme.lightAccentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Panel with the form - stretched to bottom, capped width
          Positioned(
            top: 240,
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: panelWidth),
                // Expand to fill the available height, but keep the width cap
                child: SizedBox.expand(
                  child: Material(
                    color: isDark ? AppTheme.darkCardColor : AppTheme.cardColor,
                    elevation: 6,
                    clipBehavior: Clip.antiAlias,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(40),
                        topRight: Radius.circular(40),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: screenWidth < 500 ? 16 : 24,
                        right: screenWidth < 500 ? 16 : 24,
                        top: 32,
                        bottom: 32,
                      ),
                        child: SingleChildScrollView(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                              Align(
                                alignment:
                                    isHebrew
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                child: Text(
                                  AppTranslations.getText(ref, 'login_title'),
                                  textAlign:
                                      isHebrew
                                          ? TextAlign.right
                                          : TextAlign.left,
                                  style: TextStyle(
                                    fontFamily: AppTheme.primaryFontFamily,
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: mainTextColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Email
                              AppFormContainer(
                                child: AppTextField(
                                  controller: _emailController,
                                  hintText: AppTranslations.getText(
                                    ref,
                                    'email_hint',
                                  ),
                                  prefixSvgAsset: 'assets/images/email.svg',
                                  keyboardType: TextInputType.emailAddress,
                                  textAlignOverride: isHebrew ? null : TextAlign.left,
                                  textDirectionOverride: TextDirection.ltr,
                                  onChanged: (value) => setState(() {}),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return AppTranslations.getText(
                                        ref,
                                        'email_required',
                                      );
                                    }
                                    if (!Helpers.isValidEmail(value)) {
                                      return AppTranslations.getText(
                                        ref,
                                        'invalid_email',
                                      );
                                    }
                                    return null;
                                  },
                                ),
                              ),

                              // Password
                              AppFormContainer(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: AppPasswordField(
                                  controller: _passwordController,
                                  hintText: AppTranslations.getText(
                                    ref,
                                    'password_hint',
                                  ),
                                  textAlignOverride: isHebrew ? null : TextAlign.left,
                                  textDirectionOverride: TextDirection.ltr,
                                  onChanged: (value) => setState(() {}),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return AppTranslations.getText(
                                        ref,
                                        'password_required',
                                      );
                                    }
                                    return null;
                                  },
                                ),
                              ),

                              // Error
                              if (_errorMessage != null)
                                AppErrorContainer(
                                  message: _errorMessage!,
                                  onDismiss:
                                      () =>
                                          setState(() => _errorMessage = null),
                                ),

                              // Forgot
                              Align(
                                alignment:
                                    isHebrew
                                        ? Alignment.centerLeft
                                        : Alignment.centerRight,
                                child: AppTextButton(
                                  text: AppTranslations.getText(
                                    ref,
                                    'forgot_password_link',
                                  ),
                                  onPressed: _isLoading ? null : _resetPassword,
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Login button
                              AppPrimaryButton(
                                text: AppTranslations.getText(
                                  ref,
                                  'login_button',
                                ),
                                onPressed:
                                    _isLoading
                                        ? null
                                        : _signInWithEmailAndPassword,
                                isLoading: _isLoading,
                                height: 44,
                              ),
                              const SizedBox(height: 16),

                              // Divider with text
                              Row(
                                children: [
                                  const Expanded(child: Divider()),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Text(
                                      AppTranslations.getText(
                                        ref,
                                        'login_with',
                                      ),
                                      style: TextStyle(
                                        fontFamily: AppTheme.primaryFontFamily,
                                        color: mainTextColor,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const Expanded(child: Divider()),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Socials
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Facebook
                                  InkWell(
                                    onTap:
                                        _isLoading ? null : _signInWithFacebook,
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: AppTheme.backgroundColor,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.dividerColor
                                                .withValues(alpha: 0.08),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: SvgPicture.asset(
                                          'assets/images/facebook.svg',
                                          width: 28,
                                          height: 28,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  // Google
                                  InkWell(
                                    onTap:
                                        _isLoading ? null : _signInWithGoogle,
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: AppTheme.backgroundColor,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.dividerColor
                                                .withValues(alpha: 0.08),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: SvgPicture.asset(
                                          'assets/images/google.svg',
                                          width: 28,
                                          height: 28,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Register link
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: 16 + MediaQuery.of(context).padding.bottom,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      AppTranslations.getText(
                                        ref,
                                        'want_to_save_recipes',
                                      ),
                                      style: TextStyle(
                                        color: mainTextColor,
                                        fontFamily: AppTheme.primaryFontFamily,
                                        fontSize: 14,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => context.go('/register'),
                                      child: Text(
                                        AppTranslations.getText(
                                          ref,
                                          'register_fun',
                                        ),
                                        style: const TextStyle(
                                          color: AppTheme.primaryColor,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: AppTheme.primaryFontFamily,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
