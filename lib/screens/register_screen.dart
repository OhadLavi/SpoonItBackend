import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/providers/settings_provider.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/helpers.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:recipe_keeper/widgets/auth_widgets.dart';

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
    const coralColor = Color(0xFFFF7E6B);
    const mainTextColor = Color(0xFF6E3C3F);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Stack(
        children: [
          // AuthHeader (shared with login)
          const AuthHeader(height: 320),
          // AuthPanel for the registration form
          AuthPanel(
            topMargin: 220,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Back to login
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => context.go('/login'),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: mainTextColor,
                        size: 18,
                      ),
                      label: const Text(
                        'חזרה להתחברות',
                        style: TextStyle(color: mainTextColor, fontSize: 14),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: mainTextColor,
                        padding: EdgeInsets.zero,
                        minimumSize: Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        alignment: Alignment.centerRight,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Title
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'ליצור חשבון',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'Heebo',
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: mainTextColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Name Field
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      controller: _nameController,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: mainTextColor,
                        fontWeight: FontWeight.w300,
                      ),
                      onChanged: (value) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'שם/כינוי',
                        hintStyle: TextStyle(
                          color: mainTextColor,
                          fontWeight: FontWeight.w300,
                        ),
                        prefixIcon: Icon(
                          Icons.person_outline,
                          color: mainTextColor,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'יש להזין שם';
                        }
                        return null;
                      },
                    ),
                  ),
                  // Email Field
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textAlign:
                          _emailController.text.isEmpty
                              ? TextAlign.right
                              : TextAlign.left,
                      style: const TextStyle(
                        color: mainTextColor,
                        fontWeight: FontWeight.w300,
                      ),
                      onChanged: (value) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'אימייל',
                        hintStyle: TextStyle(
                          color: mainTextColor,
                          fontWeight: FontWeight.w300,
                        ),
                        prefixIcon: Icon(
                          Icons.email_outlined,
                          color: mainTextColor,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'יש להזין אימייל';
                        }
                        if (!Helpers.isValidEmail(value)) {
                          return 'אימייל לא תקין';
                        }
                        return null;
                      },
                    ),
                  ),
                  // Password Field
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      textAlign:
                          _passwordController.text.isEmpty
                              ? TextAlign.right
                              : TextAlign.left,
                      style: const TextStyle(
                        color: mainTextColor,
                        fontWeight: FontWeight.w300,
                      ),
                      onChanged: (value) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'סיסמה',
                        hintStyle: const TextStyle(
                          color: mainTextColor,
                          fontWeight: FontWeight.w300,
                        ),
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                          color: mainTextColor,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: mainTextColor,
                            size: 20,
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
                          return 'יש להזין סיסמה';
                        }
                        return null;
                      },
                    ),
                  ),
                  // Confirm Password Field
                  Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: !_isConfirmPasswordVisible,
                      textAlign:
                          _confirmPasswordController.text.isEmpty
                              ? TextAlign.right
                              : TextAlign.left,
                      style: const TextStyle(
                        color: mainTextColor,
                        fontWeight: FontWeight.w300,
                      ),
                      onChanged: (value) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'שוב סיסמה',
                        hintStyle: const TextStyle(
                          color: mainTextColor,
                          fontWeight: FontWeight.w300,
                        ),
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                          color: mainTextColor,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isConfirmPasswordVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: mainTextColor,
                            size: 20,
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
                          return 'יש להזין שוב סיסמה';
                        }
                        if (value != _passwordController.text) {
                          return 'הסיסמאות לא תואמות';
                        }
                        return null;
                      },
                    ),
                  ),
                  // Register Button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed:
                          _isLoading ? null : _registerWithEmailAndPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: coralColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Heebo',
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      child:
                          _isLoading
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Text('יאללה נתחיל!'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
