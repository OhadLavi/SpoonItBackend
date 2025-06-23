import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/providers/settings_provider.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/helpers.dart';
import 'package:recipe_keeper/utils/translations.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithEmailAndPassword() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        await ref
            .read(authProvider.notifier)
            .signInWithEmailAndPassword(
              _emailController.text.trim(),
              _passwordController.text.trim(),
            );

        final authState = ref.read(authProvider);

        if (authState.status == AuthStatus.authenticated) {
          if (mounted) {
            context.go('/home');
          }
        } else if (authState.status == AuthStatus.error) {
          if (mounted) {
            Helpers.showSnackBar(
              context,
              authState.errorMessage ?? 'An error occurred during sign in',
              isError: true,
            );
          }
        }
      } catch (e) {
        if (mounted) {
          Helpers.showSnackBar(
            context,
            'An error occurred: ${e.toString()}',
            isError: true,
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await ref.read(authProvider.notifier).signInWithGoogle();

      final authState = ref.read(authProvider);

      if (authState.status == AuthStatus.authenticated) {
        if (mounted) {
          context.go('/home');
        }
      } else if (authState.status == AuthStatus.error) {
        if (mounted) {
          Helpers.showSnackBar(
            context,
            authState.errorMessage ?? 'An error occurred during Google sign in',
            isError: true,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Helpers.showSnackBar(
          context,
          'An error occurred: ${e.toString()}',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInAnonymously() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await ref.read(authProvider.notifier).signInAnonymously();

      final authState = ref.read(authProvider);

      if (authState.status == AuthStatus.authenticated) {
        if (mounted) {
          context.go('/home');
        }
      } else if (authState.status == AuthStatus.error) {
        if (mounted) {
          Helpers.showSnackBar(
            context,
            authState.errorMessage ??
                'An error occurred during anonymous sign in',
            isError: true,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Helpers.showSnackBar(
          context,
          'An error occurred: ${e.toString()}',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHebrew = ref.watch(settingsProvider).language == AppLanguage.hebrew;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 600;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWideScreen ? (screenWidth - 400) / 2 : 24.0,
              vertical: 24.0,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Logo
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.restaurant_menu,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // App Name
                  Text(
                    AppTranslations.getText(ref, 'app_name'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textColor,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // App Description
                  Text(
                    AppTranslations.getText(ref, 'sign_in_prompt'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      color: AppTheme.secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Email Field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    style: const TextStyle(color: AppTheme.textColor),
                    decoration: AppTheme.inputDecoration(
                      AppTranslations.getText(ref, 'email'),
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppTranslations.getText(ref, 'email_required');
                      }
                      if (!Helpers.isValidEmail(value)) {
                        return AppTranslations.getText(ref, 'invalid_email');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Password Field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    style: const TextStyle(color: AppTheme.textColor),
                    decoration: AppTheme.inputDecoration(
                      AppTranslations.getText(ref, 'password'),
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordVisible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                      ),
                    ),
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
                  const SizedBox(height: 8),

                  // Forgot Password Link
                  Align(
                    alignment:
                        isHebrew ? Alignment.centerLeft : Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        // TODO: Implement forgot password
                        Helpers.showSnackBar(
                          context,
                          AppTranslations.getText(
                            ref,
                            'feature_not_implemented',
                          ),
                        );
                      },
                      child: Text(
                        AppTranslations.getText(ref, 'forgot_password'),
                        style: const TextStyle(color: AppTheme.primaryColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Sign In Button
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _signInWithEmailAndPassword,
                    icon:
                        _isLoading
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.login),
                    label: Text(AppTranslations.getText(ref, 'sign_in')),
                  ),
                  const SizedBox(height: 16),

                  // Or Divider
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          AppTranslations.getText(ref, 'or'),
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: AppTheme.secondaryTextColor,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Google Sign In Button
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Colors.grey),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(
                      Icons.g_mobiledata_rounded,
                      size: 28,
                      color: Colors.red,
                    ),
                    label: Text(
                      AppTranslations.getText(ref, 'continue_with_google'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Anonymous Sign In Button
                  TextButton.icon(
                    onPressed: _isLoading ? null : _signInAnonymously,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: AppTheme.secondaryTextColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.person_outline),
                    label: Text(
                      AppTranslations.getText(ref, 'continue_as_guest'),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Register Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        AppTranslations.getText(ref, 'dont_have_account'),
                        style: const TextStyle(
                          color: AppTheme.secondaryTextColor,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          context.go('/register');
                        },
                        child: Text(
                          AppTranslations.getText(ref, 'register'),
                          style: const TextStyle(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Language toggle button at the bottom
                  const SizedBox(height: 32),
                  TextButton.icon(
                    onPressed: () {
                      ref.read(settingsProvider.notifier).toggleLanguage();
                    },
                    icon: const Icon(Icons.language),
                    label: Text(
                      isHebrew
                          ? AppTranslations.getText(ref, 'switch_to_english')
                          : AppTranslations.getText(ref, 'switch_to_hebrew'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
