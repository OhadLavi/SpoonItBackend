import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/helpers.dart';
import 'package:recipe_keeper/widgets/auth_widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
  String? _errorMessage;

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
        _errorMessage = null;
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
            setState(() {
              _errorMessage = Helpers.simplifyAuthError(
                authState.errorMessage ?? 'Unknown error',
              );
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = Helpers.simplifyAuthError(e.toString());
          });
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
      _errorMessage = null;
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
          setState(() {
            _errorMessage = Helpers.simplifyAuthError(
              authState.errorMessage ?? 'Unknown error',
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = Helpers.simplifyAuthError(e.toString());
        });
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
    const coralColor = AppTheme.primaryColor;
    const mainTextColor = AppTheme.textColor;

    return Scaffold(
      backgroundColor: AppTheme.cardColor,
      body: Stack(
        children: [
          // AuthHeader with welcome text
          AuthHeader(
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
                      fontFamily: AppTheme.primaryFontFamily,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.backgroundColor,
                      shadows: [
                        Shadow(
                          color: AppTheme.dividerColor.withValues(alpha: 0.26),
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
                      fontFamily: AppTheme.primaryFontFamily,
                      fontSize: 18,
                      color: AppTheme.backgroundColor,
                      shadows: [
                        Shadow(
                          color: AppTheme.dividerColor.withValues(alpha: 0.12),
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
                        fontFamily: AppTheme.primaryFontFamily,
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
                      color: AppTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.dividerColor.withValues(alpha: 0.04),
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
                      textDirection:
                          _emailController.text.isEmpty
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                      style: const TextStyle(
                        color: mainTextColor,
                        fontWeight: FontWeight.w300,
                      ),
                      onChanged: (value) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'אימייל',
                        hintStyle: TextStyle(
                          color: mainTextColor,
                          fontWeight: FontWeight.w300,
                        ),
                        prefixIcon: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SvgPicture.asset(
                            'assets/images/email.svg',
                            width: 18,
                            height: 18,
                            colorFilter: ColorFilter.mode(
                              AppTheme.textColor,
                              BlendMode.srcIn,
                            ),
                          ),
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
                      color: AppTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.dividerColor.withValues(alpha: 0.04),
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
                      textDirection:
                          _passwordController.text.isEmpty
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                      style: const TextStyle(
                        color: mainTextColor,
                        fontWeight: FontWeight.w300,
                      ),
                      onChanged: (value) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'סיסמה',
                        hintStyle: TextStyle(
                          color: mainTextColor,
                          fontWeight: FontWeight.w300,
                        ),
                        prefixIcon: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SvgPicture.asset(
                            'assets/images/password.svg',
                            width: 18,
                            height: 18,
                            colorFilter: ColorFilter.mode(
                              AppTheme.textColor,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: mainTextColor,
                            size: 18,
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
                  // Error Message Display
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.errorColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.errorColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: AppTheme.errorColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: AppTheme.errorColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Forgot Password Link (left)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        // TODO: Implement password reset
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
                        foregroundColor: AppTheme.backgroundColor,
                        disabledBackgroundColor: coralColor,
                        disabledForegroundColor: AppTheme.backgroundColor,
                        shadowColor: Colors.transparent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: AppTheme.primaryFontFamily,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      child: const Text('התחבר'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Divider with text
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'אפשר להתחבר גם עם',
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
                  // Social Login Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Facebook
                      InkWell(
                        onTap: () {
                          // TODO: Implement Facebook login
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.dividerColor.withValues(
                                  alpha: 0.08,
                                ),
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
                        onTap: _isLoading ? null : _signInWithGoogle,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.dividerColor.withValues(
                                  alpha: 0.08,
                                ),
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
                  // Register Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'רוצה לשמור מתכונים? ',
                        style: TextStyle(
                          color: mainTextColor,
                          fontFamily: AppTheme.primaryFontFamily,
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
                            fontFamily: AppTheme.primaryFontFamily,
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
