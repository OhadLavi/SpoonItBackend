import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/helpers.dart';
import 'package:recipe_keeper/widgets/auth_widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
  String? _errorMessage;

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
        _errorMessage = null;
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

  @override
  Widget build(BuildContext context) {
    const coralColor = AppTheme.primaryColor;
    const mainTextColor = AppTheme.textColor;

    return Scaffold(
      backgroundColor: AppTheme.cardColor,
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
                        fontFamily: AppTheme.primaryFontFamily,
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
                      color: AppTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.dividerColor.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      controller: _nameController,
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        color: mainTextColor,
                        fontWeight: FontWeight.w300,
                      ),
                      onChanged: (value) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'שם/כינוי',
                        hintStyle: TextStyle(
                          color: mainTextColor,
                          fontWeight: FontWeight.w300,
                        ),
                        prefixIcon: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SvgPicture.asset(
                            'assets/images/profile.svg',
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
                      color: AppTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.dividerColor.withOpacity(0.04),
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
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.dividerColor.withOpacity(0.04),
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
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
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
                      color: AppTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.dividerColor.withOpacity(0.04),
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
                      textDirection:
                          _confirmPasswordController.text.isEmpty
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                      style: const TextStyle(
                        color: mainTextColor,
                        fontWeight: FontWeight.w300,
                      ),
                      onChanged: (value) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'שוב סיסמה',
                        hintStyle: TextStyle(
                          color: mainTextColor,
                          fontWeight: FontWeight.w300,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
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
                            _isConfirmPasswordVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: mainTextColor,
                            size: 18,
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
                  // Error Message Display
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
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
                  const SizedBox(height: 16),
                  // Register Button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed:
                          _isLoading ? null : _registerWithEmailAndPassword,
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
                          fontSize: 16,
                        ),
                      ),
                      child: const Text('יאללה נתחיל!'),
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
