import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:recipe_keeper/utils/language_utils.dart';

/// Icon widget that automatically handles RTL flipping
class DirectionalIcon extends ConsumerWidget {
  final String? svgAsset;
  final IconData? iconData;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  const DirectionalIcon.svg(
    this.svgAsset, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  }) : iconData = null;

  const DirectionalIcon.icon(
    this.iconData, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  }) : svgAsset = null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (svgAsset != null) {
      final shouldFlip = LanguageUtils.shouldFlipIcon(ref, svgAsset!);
      final transform =
          shouldFlip
              ? LanguageUtils.getIconTransform(ref, svgAsset!)
              : Matrix4.identity();

      return Transform(
        alignment: Alignment.center,
        transform: transform,
        child: SvgPicture.asset(
          svgAsset!,
          width: size,
          height: size,
          colorFilter:
              color != null ? ColorFilter.mode(color!, BlendMode.srcIn) : null,
          semanticsLabel: semanticLabel,
        ),
      );
    } else if (iconData != null) {
      return Icon(
        iconData!,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
        textDirection: TextDirection.ltr, // Prevent RTL flip for Material icons
      );
    }

    return const SizedBox.shrink();
  }
}
