import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/providers/settings_provider.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/helpers.dart';
import 'package:recipe_keeper/utils/translations.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _registerWithEmailAndPassword() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        await ref
            .read(authProvider.notifier)
            .registerWithEmailAndPassword(
              _nameController.text.trim(),
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
              authState.errorMessage ?? 'An error occurred during registration',
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

  @override
  Widget build(BuildContext context) {
    final isHebrew = ref.watch(settingsProvider).language == AppLanguage.hebrew;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(AppTranslations.getText(ref, 'create_account')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.textColor,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Logo
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.restaurant_menu,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // App Description
                  Text(
                    AppTranslations.getText(ref, 'register_description'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      color: AppTheme.secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Name Field
                  TextFormField(
                    controller: _nameController,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    style: const TextStyle(color: AppTheme.textColor),
                    decoration: AppTheme.inputDecoration(
                      AppTranslations.getText(ref, 'full_name'),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppTranslations.getText(ref, 'name_required');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

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
                      if (value.length < 6) {
                        return AppTranslations.getText(
                          ref,
                          'password_too_short',
                        );
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Confirm Password Field
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: !_isConfirmPasswordVisible,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    style: const TextStyle(color: AppTheme.textColor),
                    decoration: AppTheme.inputDecoration(
                      AppTranslations.getText(ref, 'confirm_password'),
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isConfirmPasswordVisible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() {
                            _isConfirmPasswordVisible =
                                !_isConfirmPasswordVisible;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppTranslations.getText(
                          ref,
                          'confirm_password_required',
                        );
                      }
                      if (value != _passwordController.text) {
                        return AppTranslations.getText(
                          ref,
                          'passwords_dont_match',
                        );
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Register Button
                  ElevatedButton(
                    onPressed:
                        _isLoading ? null : _registerWithEmailAndPassword,
                    child:
                        _isLoading
                            ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : Text(
                              AppTranslations.getText(ref, 'create_account'),
                            ),
                  ),
                  const SizedBox(height: 24),

                  // Login Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        AppTranslations.getText(ref, 'already_have_account'),
                        style: const TextStyle(
                          color: AppTheme.secondaryTextColor,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          context.go('/login');
                        },
                        child: Text(
                          AppTranslations.getText(ref, 'sign_in'),
                          style: const TextStyle(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ],
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
