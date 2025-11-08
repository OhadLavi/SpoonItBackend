import 'package:flutter/material.dart';
import 'package:spoonit/utils/app_theme.dart';

class AppLoadingIndicator extends StatelessWidget {
  final double? size;
  final Color? color;
  final double? strokeWidth;
  final String? message;
  final TextStyle? messageStyle;
  final MainAxisAlignment alignment;
  final bool showMessage;
  final EdgeInsetsGeometry? padding;

  const AppLoadingIndicator({
    super.key,
    this.size,
    this.color,
    this.strokeWidth,
    this.message,
    this.messageStyle,
    this.alignment = MainAxisAlignment.center,
    this.showMessage = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveColor = color ?? AppTheme.primaryColor;
    final effectiveSize = size ?? 24.0;
    final effectiveStrokeWidth = strokeWidth ?? 2.0;
    final effectivePadding = padding ?? const EdgeInsets.all(16);

    return Padding(
      padding: effectivePadding,
      child: Column(
        mainAxisAlignment: alignment,
        children: [
          SizedBox(
            width: effectiveSize,
            height: effectiveSize,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(effectiveColor),
              strokeWidth: effectiveStrokeWidth,
            ),
          ),
          if (showMessage && message != null) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              style:
                  messageStyle ??
                  TextStyle(
                    color: isDark ? AppTheme.darkTextColor : AppTheme.textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: AppTheme.primaryFontFamily,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-screen loading indicator
class AppFullScreenLoading extends StatelessWidget {
  final String? message;
  final Color? backgroundColor;
  final Color? indicatorColor;
  final double? indicatorSize;
  final double? strokeWidth;

  const AppFullScreenLoading({
    super.key,
    this.message,
    this.backgroundColor,
    this.indicatorColor,
    this.indicatorSize,
    this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveBackgroundColor =
        backgroundColor ??
        (isDark ? AppTheme.darkBackgroundColor : AppTheme.backgroundColor);

    return Container(
      color: effectiveBackgroundColor,
      child: Center(
        child: AppLoadingIndicator(
          size: indicatorSize,
          color: indicatorColor,
          strokeWidth: strokeWidth,
          message: message,
          showMessage: message != null,
          padding: const EdgeInsets.all(32),
        ),
      ),
    );
  }
}

/// Inline loading indicator for buttons and small spaces
class AppInlineLoading extends StatelessWidget {
  final double? size;
  final Color? color;
  final double? strokeWidth;

  const AppInlineLoading({super.key, this.size, this.color, this.strokeWidth});

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppTheme.primaryColor;
    final effectiveSize = size ?? 16.0;
    final effectiveStrokeWidth = strokeWidth ?? 2.0;

    return SizedBox(
      width: effectiveSize,
      height: effectiveSize,
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(effectiveColor),
        strokeWidth: effectiveStrokeWidth,
      ),
    );
  }
}

/// Loading indicator with custom animation
class AppCustomLoading extends StatefulWidget {
  final double? size;
  final Color? color;
  final Duration duration;
  final String? message;
  final bool showMessage;

  const AppCustomLoading({
    super.key,
    this.size,
    this.color,
    this.duration = const Duration(seconds: 2),
    this.message,
    this.showMessage = false,
  });

  @override
  State<AppCustomLoading> createState() => _AppCustomLoadingState();
}

class _AppCustomLoadingState extends State<AppCustomLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveColor = widget.color ?? AppTheme.primaryColor;
    final effectiveSize = widget.size ?? 24.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Opacity(
              opacity: _animation.value,
              child: Container(
                width: effectiveSize,
                height: effectiveSize,
                decoration: BoxDecoration(
                  color: effectiveColor,
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        ),
        if (widget.showMessage && widget.message != null) ...[
          const SizedBox(height: 12),
          Text(
            widget.message!,
            style: TextStyle(
              color: isDark ? AppTheme.darkTextColor : AppTheme.textColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: AppTheme.primaryFontFamily,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// Loading indicator for lists and grids
class AppListLoading extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int)? itemBuilder;
  final EdgeInsetsGeometry? padding;
  final double? itemHeight;

  const AppListLoading({
    super.key,
    this.itemCount = 3,
    this.itemBuilder,
    this.padding,
    this.itemHeight,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveItemHeight = itemHeight ?? 80.0;

    return ListView.builder(
      padding: padding,
      itemCount: itemCount,
      itemBuilder:
          itemBuilder ??
          (context, index) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              height: effectiveItemHeight,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCardColor : AppTheme.cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const AppLoadingIndicator(
                size: 24,
                padding: EdgeInsets.all(16),
              ),
            );
          },
    );
  }
}





