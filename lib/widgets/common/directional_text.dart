import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/utils/language_utils.dart';

/// Text widget that automatically aligns based on language
class DirectionalText extends ConsumerWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final TextDirection? textDirection;

  const DirectionalText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.textDirection,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign ?? LanguageUtils.getTextAlignment(ref),
      textDirection: textDirection ?? LanguageUtils.getTextDirection(ref),
    );
  }
}

