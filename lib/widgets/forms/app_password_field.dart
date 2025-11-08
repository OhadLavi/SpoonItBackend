import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/widgets/forms/app_text_field.dart';

class AppPasswordField extends ConsumerStatefulWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function()? onTap;
  final bool readOnly;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry? contentPadding;
  final bool enabled;
  final String? errorText;
  final Color? fillColor;
  final Color? borderColor;
  final double? borderRadius;
  final bool autofocus;
  final TextAlign? textAlignOverride;
  final TextDirection? textDirectionOverride;

  const AppPasswordField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.validator,
    this.onChanged,
    this.onTap,
    this.readOnly = false,
    this.maxLength,
    this.textInputAction,
    this.focusNode,
    this.contentPadding,
    this.enabled = true,
    this.errorText,
    this.fillColor,
    this.borderColor,
    this.borderRadius,
    this.autofocus = false,
    this.textAlignOverride,
    this.textDirectionOverride,
  });

  @override
  ConsumerState<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends ConsumerState<AppPasswordField> {
  bool _obscureText = true;

  void _toggleObscureText() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppTextField(
      controller: widget.controller,
      hintText: widget.hintText,
      labelText: widget.labelText,
      prefixSvgAsset: 'assets/images/password.svg',
      obscureText: _obscureText,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onTap: widget.onTap,
      readOnly: widget.readOnly,
      maxLength: widget.maxLength,
      textInputAction: widget.textInputAction,
      focusNode: widget.focusNode,
      contentPadding: widget.contentPadding,
      enabled: widget.enabled,
      errorText: widget.errorText,
      fillColor: widget.fillColor,
      borderColor: widget.borderColor,
      borderRadius: widget.borderRadius,
      autofocus: widget.autofocus,
      textAlignOverride: widget.textAlignOverride,
      textDirectionOverride: widget.textDirectionOverride,
      suffixIcon: IconButton(
        icon: Icon(
          _obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: isDark ? AppTheme.darkTextColor : AppTheme.textColor,
        ),
        onPressed: _toggleObscureText,
        iconSize: 20,
      ),
    );
  }
}

