import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/utils/translations.dart';
import 'package:spoonit/widgets/feedback/app_loading_indicator.dart';

class AppEmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? action;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final MainAxisAlignment alignment;
  final Color? iconColor;
  final Color? titleColor;
  final Color? subtitleColor;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final double? iconSize;
  final double? spacing;

  const AppEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.action,
    this.padding,
    this.margin,
    this.alignment = MainAxisAlignment.center,
    this.iconColor,
    this.titleColor,
    this.subtitleColor,
    this.titleStyle,
    this.subtitleStyle,
    this.iconSize,
    this.spacing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Theme-aware colors
    final effectiveIconColor =
        iconColor ??
        (isDark
            ? AppTheme.darkTextColor.withValues(alpha: 0.5)
            : AppTheme.secondaryTextColor);
    final effectiveTitleColor =
        titleColor ?? (isDark ? AppTheme.darkTextColor : AppTheme.textColor);
    final effectiveSubtitleColor =
        subtitleColor ??
        (isDark
            ? AppTheme.darkTextColor.withValues(alpha: 0.7)
            : AppTheme.textColor.withValues(alpha: 0.7));

    final effectiveIconSize = iconSize ?? 80.0;
    final effectiveSpacing = spacing ?? 16.0;
    final effectivePadding = padding ?? const EdgeInsets.all(32);
    final effectiveMargin = margin ?? EdgeInsets.zero;

    return Container(
      margin: effectiveMargin,
      padding: effectivePadding,
      child: Column(
        mainAxisAlignment: alignment,
        children: [
          if (icon != null) ...[
            Icon(icon, size: effectiveIconSize, color: effectiveIconColor),
            SizedBox(height: effectiveSpacing),
          ],
          Text(
            title,
            style:
                titleStyle ??
                TextStyle(
                  color: effectiveTitleColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppTheme.primaryFontFamily,
                ),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            SizedBox(height: effectiveSpacing * 0.5),
            Text(
              subtitle!,
              style:
                  subtitleStyle ??
                  TextStyle(
                    color: effectiveSubtitleColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    fontFamily: AppTheme.primaryFontFamily,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[SizedBox(height: effectiveSpacing), action!],
        ],
      ),
    );
  }
}

/// Specialized empty state for "no data" scenarios
class AppNoDataState extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const AppNoDataState({
    super.key,
    this.title,
    this.subtitle,
    this.action,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: title ?? 'No data available',
      subtitle: subtitle ?? 'There\'s nothing to show here yet.',
      icon: Icons.inbox_outlined,
      action: action,
      padding: padding,
      margin: margin,
    );
  }
}

/// Specialized empty state for "not found" scenarios
class AppNotFoundState extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const AppNotFoundState({
    super.key,
    this.title,
    this.subtitle,
    this.action,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: title ?? 'Not found',
      subtitle: subtitle ?? 'The item you\'re looking for doesn\'t exist.',
      icon: Icons.search_off,
      action: action,
      padding: padding,
      margin: margin,
    );
  }
}

/// Specialized empty state for error scenarios
class AppErrorState extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const AppErrorState({
    super.key,
    this.title,
    this.subtitle,
    this.action,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: title ?? 'Something went wrong',
      subtitle:
          subtitle ?? 'We encountered an error while loading this content.',
      icon: Icons.error_outline,
      iconColor: AppTheme.errorColor,
      action: action,
      padding: padding,
      margin: margin,
    );
  }
}

/// Specialized empty state for loading scenarios
class AppLoadingState extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const AppLoadingState({
    super.key,
    this.title,
    this.subtitle,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: title ?? 'Loading...',
      subtitle: subtitle ?? 'Please wait while we fetch your data.',
      icon: Icons.hourglass_empty,
      action: const AppLoadingIndicator(),
      padding: padding,
      margin: margin,
    );
  }
}

/// Specialized empty state for search results
class AppNoSearchResultsState extends ConsumerWidget {
  final String? searchQuery;
  final Widget? action;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const AppNoSearchResultsState({
    super.key,
    this.searchQuery,
    this.action,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = AppTranslations.getText(ref, 'no_results_found_title');
    final subtitle = searchQuery != null
        ? AppTranslations.getText(ref, 'no_results_found')
            .replaceAll('{query}', '$searchQuery')
        : AppTranslations.getText(ref, 'try_different_search');
    
    return Center(
      child: AppEmptyState(
        title: title,
        subtitle: subtitle,
        icon: Icons.search_off,
        action: action,
        padding: padding ?? const EdgeInsets.only(bottom: 100),
        margin: margin,
      ),
    );
  }
}

/// Specialized empty state for lists
class AppEmptyListState extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const AppEmptyListState({
    super.key,
    this.title,
    this.subtitle,
    this.action,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: title ?? 'List is empty',
      subtitle: subtitle ?? 'Add some items to get started.',
      icon: Icons.list_alt,
      action: action,
      padding: padding,
      margin: margin,
    );
  }
}
