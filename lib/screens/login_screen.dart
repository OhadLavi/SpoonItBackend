import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/providers/settings_provider.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/helpers.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:recipe_keeper/widgets/auth_widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:recipe_keeper/utils/responsive_utils.dart';
import 'package:recipe_keeper/utils/language_utils.dart';
import 'package:recipe_keeper/services/rate_limit_service.dart';
import 'package:recipe_keeper/services/audit_logger_service.dart';

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

      // Clear rate limiting on successful login
      await RateLimitService.clearAttemptsAsync(email);

      if (mounted) context.go('/home');
    } catch (e) {
      // Record failed attempt
      await RateLimitService.recordFailedAttemptAsync(email);

      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
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
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
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
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
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
                                          : TextAlign.left,
                                  textDirection:
                                      _emailController.text.isEmpty
                                          ? (isHebrew
                                              ? TextDirection.rtl
                                              : TextDirection.ltr)
                                          : TextDirection.ltr,
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
                                margin: const EdgeInsets.only(bottom: 8),
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
                                          : TextAlign.left,
                                  textDirection:
                                      _passwordController.text.isEmpty
                                          ? (isHebrew
                                              ? TextDirection.rtl
                                              : TextDirection.ltr)
                                          : TextDirection.ltr,
                                  style: TextStyle(
                                    color: mainTextColor,
                                    fontWeight: FontWeight.w300,
                                  ),
                                  onChanged: (value) => setState(() {}),
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
                                    return null;
                                  },
                                ),
                              ),

                              // Error
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 8),
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

                              // Forgot
                              Align(
                                alignment:
                                    isHebrew
                                        ? Alignment.centerLeft
                                        : Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _isLoading ? null : _resetPassword,
                                  child: Text(
                                    AppTranslations.getText(
                                      ref,
                                      'forgot_password_link',
                                    ),
                                    style: TextStyle(
                                      color: mainTextColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Login button
                              SizedBox(
                                height: 44,
                                child: ElevatedButton(
                                  onPressed:
                                      _isLoading
                                          ? null
                                          : _signInWithEmailAndPassword,
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
                                      fontSize: 18,
                                    ),
                                  ),
                                  child: Text(
                                    AppTranslations.getText(
                                      ref,
                                      'login_button',
                                    ),
                                  ),
                                ),
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
                              Row(
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
