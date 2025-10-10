import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/utils/language_utils.dart';

/// Row widget that automatically reverses children for RTL
class LanguageAwareRow extends ConsumerWidget {
  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;

  const LanguageAwareRow({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.mainAxisSize = MainAxisSize.max,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHebrew = LanguageUtils.isHebrew(ref);

    return Row(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: mainAxisSize,
      textDirection: isHebrew ? TextDirection.rtl : TextDirection.ltr,
      children: isHebrew ? children.reversed.toList() : children,
    );
  }
}

