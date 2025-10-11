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
import 'package:spoonit/services/password_validator_service.dart';
import 'package:spoonit/services/input_sanitizer_service.dart';

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
  PasswordStrength _passwordStrength = PasswordStrength.weak;

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
      // Sanitize inputs
      final sanitizedName = InputSanitizer.sanitizeDisplayName(
        _nameController.text.trim(),
      );
      final sanitizedEmail = InputSanitizer.sanitizeEmail(
        _emailController.text.trim(),
      );
      final password = _passwordController.text.trim();

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        await ref
            .read(authProvider.notifier)
            .registerWithEmailAndPassword(
              sanitizedName,
              sanitizedEmail,
              password,
            );

        final authState = ref.read(authProvider);

        if (authState.status == AuthStatus.authenticated) {
          if (mounted) context.go('/home');
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
    final settings = ref.watch(settingsProvider);
    final isDark = settings.themeMode == ThemeMode.dark;

    final mainTextColor = isDark ? AppTheme.darkTextColor : AppTheme.textColor;

    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 700;
    final panelWidth = isWeb ? 500.0 : screenWidth;

    final isHebrew = ref.watch(settingsProvider).language == AppLanguage.hebrew;

    return Scaffold(
      resizeToAvoidBottomInset: true,
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
                  crossAxisAlignment:
                      isHebrew
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.start,
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
                constraints: BoxConstraints(
                  maxWidth: isWeb ? 500 : double.infinity,
                ),
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
                      padding: EdgeInsets.symmetric(
                        horizontal: screenWidth < 500 ? 16 : 24,
                        vertical: 32,
                      ),
                      // Scroll if content overflows on short screens
                      child: SingleChildScrollView(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Back to login
                              Align(
                                alignment:
                                    isHebrew
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () => context.go('/login'),
                                  icon: Icon(
                                    Icons.arrow_back,
                                    color: mainTextColor,
                                    size: 18,
                                  ),
                                  label: Text(
                                    AppTranslations.getText(
                                      ref,
                                      'back_to_login',
                                    ),
                                    style: TextStyle(
                                      color: mainTextColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: mainTextColor,
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 0),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    alignment: Alignment.centerRight,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 0),

                              Align(
                                alignment:
                                    isHebrew
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                child: Text(
                                  AppTranslations.getText(
                                    ref,
                                    'create_account',
                                  ),
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

                              // Name
                              Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color:
                                      isDark
                                          ? AppTheme.darkCardColor
                                          : AppTheme.backgroundColor,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color:
                                        isDark
                                            ? AppTheme.darkDividerColor
                                            : AppTheme.dividerColor,
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.dividerColor.withValues(
                                        alpha: 0.04,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: TextFormField(
                                  controller: _nameController,
                                  textAlign:
                                      isHebrew
                                          ? TextAlign.right
                                          : TextAlign.left,
                                  textDirection:
                                      isHebrew
                                          ? TextDirection.rtl
                                          : TextDirection.ltr,
                                  style: TextStyle(
                                    color: mainTextColor,
                                    fontWeight: FontWeight.w300,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: AppTranslations.getText(
                                      ref,
                                      'name_hint',
                                    ),
                                    hintStyle: TextStyle(
                                      color: mainTextColor,
                                      fontWeight: FontWeight.w300,
                                    ),
                                    prefixIcon: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: SvgPicture.asset(
                                        'assets/images/profile.svg',
                                        width: 18,
                                        height: 18,
                                        colorFilter: const ColorFilter.mode(
                                          AppTheme.textColor,
                                          BlendMode.srcIn,
                                        ),
                                      ),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedErrorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    disabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 18,
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return AppTranslations.getText(
                                        ref,
                                        'name_required',
                                      );
                                    }
                                    return null;
                                  },
                                ),
                              ),

                              // Email
                              Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color:
                                      isDark
                                          ? AppTheme.darkCardColor
                                          : AppTheme.backgroundColor,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color:
                                        isDark
                                            ? AppTheme.darkDividerColor
                                            : AppTheme.dividerColor,
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.dividerColor.withValues(
                                        alpha: 0.04,
                                      ),
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
                                          ? (isHebrew
                                              ? TextAlign.right
                                              : TextAlign.left)
                                          : (isHebrew
                                              ? TextAlign.left
                                              : TextAlign.left),
                                  textDirection:
                                      _emailController.text.isEmpty
                                          ? (isHebrew
                                              ? TextDirection.rtl
                                              : TextDirection.ltr)
                                          : (isHebrew
                                              ? TextDirection.ltr
                                              : TextDirection.ltr),
                                  style: TextStyle(
                                    color: mainTextColor,
                                    fontWeight: FontWeight.w300,
                                  ),
                                  onChanged: (value) => setState(() {}),
                                  decoration: InputDecoration(
                                    hintText: AppTranslations.getText(
                                      ref,
                                      'email_hint',
                                    ),
                                    hintStyle: TextStyle(
                                      color: mainTextColor,
                                      fontWeight: FontWeight.w300,
                                    ),
                                    prefixIcon: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: SvgPicture.asset(
                                        'assets/images/email.svg',
                                        width: 18,
                                        height: 18,
                                        colorFilter: const ColorFilter.mode(
                                          AppTheme.textColor,
                                          BlendMode.srcIn,
                                        ),
                                      ),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedErrorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    disabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 18,
                                    ),
                                  ),
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
                              Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color:
                                      isDark
                                          ? AppTheme.darkCardColor
                                          : AppTheme.backgroundColor,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color:
                                        isDark
                                            ? AppTheme.darkDividerColor
                                            : AppTheme.dividerColor,
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.dividerColor.withValues(
                                        alpha: 0.04,
                                      ),
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
                                          ? (isHebrew
                                              ? TextAlign.right
                                              : TextAlign.left)
                                          : (isHebrew
                                              ? TextAlign.left
                                              : TextAlign.left),
                                  textDirection:
                                      _passwordController.text.isEmpty
                                          ? (isHebrew
                                              ? TextDirection.rtl
                                              : TextDirection.ltr)
                                          : (isHebrew
                                              ? TextDirection.ltr
                                              : TextDirection.ltr),
                                  style: TextStyle(
                                    color: mainTextColor,
                                    fontWeight: FontWeight.w300,
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _passwordStrength =
                                          PasswordValidator.calculateStrength(
                                            value,
                                          );
                                    });
                                  },
                                  decoration: InputDecoration(
                                    hintText: AppTranslations.getText(
                                      ref,
                                      'password_hint',
                                    ),
                                    hintStyle: TextStyle(
                                      color: mainTextColor,
                                      fontWeight: FontWeight.w300,
                                    ),
                                    prefixIcon: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: SvgPicture.asset(
                                        'assets/images/password.svg',
                                        width: 18,
                                        height: 18,
                                        colorFilter: const ColorFilter.mode(
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
                                          _isPasswordVisible =
                                              !_isPasswordVisible;
                                        });
                                      },
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedErrorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    disabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 18,
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return AppTranslations.getText(
                                        ref,
                                        'password_required',
                                      );
                                    }

                                    // Use password validator
                                    final validationError =
                                        PasswordValidator.validatePassword(
                                          value,
                                        );
                                    if (validationError != null) {
                                      return AppTranslations.getText(
                                        ref,
                                        validationError,
                                      );
                                    }

                                    return null;
                                  },
                                ),
                              ),

                              // Password strength indicator
                              if (_passwordController.text.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: PasswordValidator.getStrengthColor(
                                      _passwordStrength,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: PasswordValidator.getStrengthColor(
                                        _passwordStrength,
                                      ).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.security,
                                        color:
                                            PasswordValidator.getStrengthColor(
                                              _passwordStrength,
                                            ),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        AppTranslations.getText(
                                          ref,
                                          PasswordValidator.getStrengthText(
                                            _passwordStrength,
                                          ),
                                        ),
                                        style: TextStyle(
                                          color:
                                              PasswordValidator.getStrengthColor(
                                                _passwordStrength,
                                              ),
                                          fontWeight: FontWeight.w500,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              // Confirm password
                              Container(
                                margin: const EdgeInsets.only(bottom: 24),
                                decoration: BoxDecoration(
                                  color:
                                      isDark
                                          ? AppTheme.darkCardColor
                                          : AppTheme.backgroundColor,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color:
                                        isDark
                                            ? AppTheme.darkDividerColor
                                            : AppTheme.dividerColor,
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.dividerColor.withValues(
                                        alpha: 0.04,
                                      ),
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
                                          ? (isHebrew
                                              ? TextAlign.right
                                              : TextAlign.left)
                                          : (isHebrew
                                              ? TextAlign.left
                                              : TextAlign.left),
                                  textDirection:
                                      _confirmPasswordController.text.isEmpty
                                          ? (isHebrew
                                              ? TextDirection.rtl
                                              : TextDirection.ltr)
                                          : (isHebrew
                                              ? TextDirection.ltr
                                              : TextDirection.ltr),
                                  style: TextStyle(
                                    color: mainTextColor,
                                    fontWeight: FontWeight.w300,
                                  ),
                                  onChanged: (value) => setState(() {}),
                                  decoration: InputDecoration(
                                    hintText: AppTranslations.getText(
                                      ref,
                                      'confirm_password_hint',
                                    ),
                                    hintStyle: TextStyle(
                                      color: mainTextColor,
                                      fontWeight: FontWeight.w300,
                                    ),
                                    prefixIcon: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: SvgPicture.asset(
                                        'assets/images/password.svg',
                                        width: 18,
                                        height: 18,
                                        colorFilter: const ColorFilter.mode(
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
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedErrorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    disabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 18,
                                    ),
                                  ),
                                  validator: (value) {
                                    return PasswordValidator.validatePasswordConfirmation(
                                              _passwordController.text,
                                              value ?? '',
                                            ) !=
                                            null
                                        ? AppTranslations.getText(
                                          ref,
                                          PasswordValidator.validatePasswordConfirmation(
                                            _passwordController.text,
                                            value ?? '',
                                          )!,
                                        )
                                        : null;
                                  },
                                ),
                              ),

                              // Error
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.errorColor.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppTheme.errorColor.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        color: AppTheme.errorColor,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: const TextStyle(
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
                              const SizedBox(height: 8),

                              // Register
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: ElevatedButton(
                                  onPressed:
                                      _isLoading
                                          ? null
                                          : _registerWithEmailAndPassword,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColor,
                                    foregroundColor: AppTheme.backgroundColor,
                                    disabledBackgroundColor:
                                        AppTheme.primaryColor,
                                    disabledForegroundColor:
                                        AppTheme.backgroundColor,
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
                                  child: Text(
                                    AppTranslations.getText(ref, 'lets_start'),
                                  ),
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
