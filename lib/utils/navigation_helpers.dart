import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spoonit/utils/language_utils.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/utils/translations.dart';
import 'package:spoonit/widgets/settings_menu.dart';
import 'package:spoonit/widgets/painters/wavy_button_painter.dart';
import 'package:spoonit/widgets/common/directional_text.dart';

/// Navigation helpers for consistent modal and dialog patterns
class NavigationHelpers {
  /// Show language-aware dialog with automatic directionality
  static Future<T?> showLanguageAwareDialog<T>({
    required BuildContext context,
    required WidgetRef ref,
    required Widget child,
    bool barrierDismissible = true,
    Color? barrierColor,
    String? barrierLabel,
    Duration transitionDuration = const Duration(milliseconds: 300),
  }) {
    final isHebrew = LanguageUtils.isHebrew(ref);

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      barrierColor:
          barrierColor ?? AppTheme.dividerColor.withValues(alpha: 0.54),
      transitionDuration: transitionDuration,
      pageBuilder: (ctx, anim, secAnim) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, secAnim, child) {
        return Directionality(
          textDirection: isHebrew ? TextDirection.rtl : TextDirection.ltr,
          child: child,
        );
      },
    );
  }

  /// Show language-aware bottom sheet with automatic directionality
  static Future<T?> showLanguageAwareBottomSheet<T>({
    required BuildContext context,
    required WidgetRef ref,
    required Widget child,
    Color? backgroundColor,
    ShapeBorder? shape,
    bool isScrollControlled = false,
    bool useRootNavigator = false,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    final isHebrew = LanguageUtils.isHebrew(ref);

    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: backgroundColor ?? AppTheme.backgroundColor,
      shape:
          shape ??
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
      isScrollControlled: isScrollControlled,
      useRootNavigator: useRootNavigator,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      builder:
          (context) => Directionality(
            textDirection: isHebrew ? TextDirection.rtl : TextDirection.ltr,
            child: child,
          ),
    );
  }

  /// Show settings panel with slide animation
  static void showSettingsPanel(BuildContext context, WidgetRef ref) {
    final isHebrew = LanguageUtils.isHebrew(ref);
    final hostContext = context;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: AppTheme.dividerColor.withValues(alpha: 0.54),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim, secAnim) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, secAnim, child) {
        final w = MediaQuery.of(context).size.width;
        final h = MediaQuery.of(context).size.height;
        final panelW = w < 520 ? 320.0 : 380.0;

        return SlideTransition(
          position: Tween<Offset>(
            begin: isHebrew ? const Offset(1, 0) : const Offset(-1, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          ),
          child: Align(
            alignment: isHebrew ? Alignment.centerRight : Alignment.centerLeft,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Panel
                Container(
                  width: panelW,
                  height: h,
                  decoration: const BoxDecoration(
                    color: AppTheme.uiAccentColor,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        textTheme: Theme.of(context).textTheme.copyWith(
                          bodyMedium: const TextStyle(
                            color: AppTheme.lightAccentColor,
                            fontFamily: AppTheme.primaryFontFamily,
                          ),
                        ),
                      ),
                      child: Directionality(
                        textDirection:
                            isHebrew ? TextDirection.rtl : TextDirection.ltr,
                        child: SettingsMenu(hostContext: hostContext),
                      ),
                    ),
                  ),
                ),

                // Close button positioned based on language direction
                Positioned(
                  left: isHebrew ? -18 : null,
                  right: isHebrew ? null : -18,
                  top: 44,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: CustomPaint(
                      size: const Size(32, 32),
                      painter: const WavyButtonPainter(),
                      child: Center(
                        child: Icon(
                          isHebrew ? Icons.chevron_right : Icons.chevron_left,
                          size: 20,
                          color: AppTheme.primaryColor,
                          textDirection: TextDirection.ltr, // prevent RTL flip
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Show add recipe options bottom sheet
  static void showAddRecipeOptions(BuildContext context, WidgetRef ref) {
    showLanguageAwareBottomSheet(
      context: context,
      ref: ref,
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.backgroundColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DirectionalText(
                AppTranslations.getText(ref, 'add_recipe'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: AppTheme.primaryFontFamily,
                  color: AppTheme.textColor,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.edit, color: AppTheme.primaryColor),
                title: DirectionalText(
                  AppTranslations.getText(ref, 'create_new_recipe'),
                  style: const TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    color: AppTheme.textColor,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/add-recipe');
                },
              ),
              ListTile(
                leading: const Icon(Icons.link, color: AppTheme.primaryColor),
                title: DirectionalText(
                  AppTranslations.getText(ref, 'import_recipe'),
                  style: const TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    color: AppTheme.textColor,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/import-recipe');
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt,
                  color: AppTheme.primaryColor,
                ),
                title: DirectionalText(
                  AppTranslations.getText(ref, 'scan_recipe'),
                  style: const TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    color: AppTheme.textColor,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/scan-recipe');
                },
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
