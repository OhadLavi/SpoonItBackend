import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/providers/settings_provider.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/helpers.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:recipe_keeper/widgets/auth_widgets.dart';

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
    const coralColor = Color(0xFFFF7E6B);
    const mainTextColor = Color(0xFF6E3C3F);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Stack(
        children: [
          // AuthHeader with welcome text
          const AuthHeader(
            height: 320,
            child: Padding(
              padding: EdgeInsets.only(top: 100, right: 32, left: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    'שלום!',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'Heebo',
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'ברוכים הבאים ל-SpoonIt',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'Heebo',
                      fontSize: 18,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black12,
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // AuthPanel for the login form
          AuthPanel(
            topMargin: 220,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'התחברות',
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
                    margin: const EdgeInsets.only(bottom: 8),
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
                        prefixIcon: IconButton(
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
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
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
                  // Forgot Password Link (left)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        Helpers.showSnackBar(
                          context,
                          'פיצ׳ר שחזור סיסמה יגיע בקרוב',
                        );
                      },
                      child: const Text(
                        'שכחתי סיסמה',
                        style: TextStyle(color: mainTextColor, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Login Button
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed:
                          _isLoading ? null : _signInWithEmailAndPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: coralColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Heebo',
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
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
                              : const Text('התחבר'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Divider with text
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: const Text(
                          'אפשר להתחבר גם עם',
                          style: TextStyle(
                            fontFamily: 'Heebo',
                            color: mainTextColor,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Social Login Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Facebook
                      InkWell(
                        onTap: () {
                          Helpers.showSnackBar(
                            context,
                            'פייסבוק לא נתמך עדיין',
                          );
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.facebook,
                            color: Color(0xFF1877F3),
                            size: 28,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Google
                      InkWell(
                        onTap: _isLoading ? null : _signInWithGoogle,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Image.network(
                              'https://upload.wikimedia.org/wikipedia/commons/5/53/Google_%22G%22_Logo.svg',
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (context, error, stackTrace) => Icon(
                                    Icons.g_mobiledata_rounded,
                                    color: Color(0xFF4285F4),
                                    size: 28,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Register Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'רוצה לשמור מתכונים? ',
                        style: TextStyle(
                          color: mainTextColor,
                          fontFamily: 'Heebo',
                          fontSize: 14,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          context.go('/register');
                        },
                        child: const Text(
                          'הרשמה בכיף',
                          style: TextStyle(
                            color: coralColor,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Heebo',
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
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
