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
import 'package:spoonit/widgets/forms/app_text_field.dart';
import 'package:spoonit/widgets/forms/app_password_field.dart';
import 'package:spoonit/widgets/forms/app_form_container.dart';
import 'package:spoonit/widgets/buttons/app_primary_button.dart';
import 'package:spoonit/widgets/feedback/app_error_container.dart';
import 'package:spoonit/services/error_handler_service.dart';

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
              _errorMessage =
                  ErrorHandlerService.handleAuthError(
                    authState.errorMessage ?? 'Unknown error',
                    ref,
                  ).userMessage;
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage =
                ErrorHandlerService.handleAuthError(e, ref).userMessage;
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
                              AppFormContainer(
                                child: AppTextField(
                                  controller: _nameController,
                                  hintText: AppTranslations.getText(
                                    ref,
                                    'name_hint',
                                  ),
                                  prefixSvgAsset: 'assets/images/profile.svg',
                                  textAlignOverride: isHebrew && Helpers.isEnglishText(_nameController.text) ? TextAlign.left : null,
                                  textDirectionOverride: isHebrew && Helpers.isEnglishText(_nameController.text) ? TextDirection.ltr : null,
                                  onChanged: (value) => setState(() {}),
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
                                child: AppPasswordField(
                                  controller: _passwordController,
                                  hintText: AppTranslations.getText(
                                    ref,
                                    'password_hint',
                                  ),
                                  textAlignOverride: isHebrew ? null : TextAlign.left,
                                  textDirectionOverride: TextDirection.ltr,
                                  onChanged: (value) {
                                    setState(() {
                                      _passwordStrength =
                                          PasswordValidator.calculateStrength(
                                            value,
                                          );
                                    });
                                  },
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return AppTranslations.getText(
                                        ref,
                                        'password_required',
                                      );
                                    }
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

                              // Password strength indicator (tightly below password field)
                              if (_passwordController.text.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Padding(
                                  padding: const EdgeInsets.only(left: 16),
                                  child: Text(
                                    AppTranslations.getText(
                                      ref,
                                      PasswordValidator.getStrengthText(
                                        _passwordStrength,
                                      ),
                                    ),
                                    style: TextStyle(
                                      color: AppTheme.errorColor,
                                      fontWeight: FontWeight.w400,
                                      fontSize: 12,
                                      fontFamily: AppTheme.secondaryFontFamily,
                                    ),
                                  ),
                                ),
                              ],

                              // Confirm password
                              AppFormContainer(
                                margin: const EdgeInsets.only(bottom: 24),
                                child: AppPasswordField(
                                  controller: _confirmPasswordController,
                                  hintText: AppTranslations.getText(
                                    ref,
                                    'confirm_password_hint',
                                  ),
                                  onChanged: (value) => setState(() {}),
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
                              if (_errorMessage != null)
                                AppErrorContainer(
                                  message: _errorMessage!,
                                  onDismiss:
                                      () =>
                                          setState(() => _errorMessage = null),
                                ),
                              const SizedBox(height: 8),

                              // Register
                              AppPrimaryButton(
                                text: AppTranslations.getText(
                                  ref,
                                  'lets_start',
                                ),
                                onPressed:
                                    _isLoading
                                        ? null
                                        : _registerWithEmailAndPassword,
                                isLoading: _isLoading,
                                width: double.infinity,
                                height: 44,
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
