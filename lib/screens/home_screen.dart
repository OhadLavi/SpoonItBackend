import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/services/category_service.dart';
import 'package:recipe_keeper/models/category.dart';
import 'package:recipe_keeper/widgets/settings_menu.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';
import 'package:recipe_keeper/widgets/add_category_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/services/category_icon_service.dart';
import 'package:recipe_keeper/providers/settings_provider.dart';
import 'dart:ui';
import 'package:recipe_keeper/utils/translations.dart';

final gridViewProvider = Provider<bool>((ref) => false);
final favoritesUIProvider = Provider<Set<String>>((ref) => <String>{});
final categoryServiceProvider = Provider((ref) => CategoryService());
final userCategoriesProvider = StreamProvider.family<List<Category>, String>((
  ref,
  userId,
) {
  final service = ref.watch(categoryServiceProvider);
  return service.getCategories(userId);
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int selectedCategoryIndex = -1;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Default categories for new users using SVG icons
  final List<Map<String, dynamic>> _defaultCategories = [
    {'label': 'pastries', 'iconKey': 'pastries'},
    {'label': 'main_dishes', 'iconKey': 'main'},
    {'label': 'sides', 'iconKey': 'sides'},
    {'label': 'cookies', 'iconKey': 'cookies'},
    {'label': 'cakes', 'iconKey': 'cakes'},
    {'label': 'salads', 'iconKey': 'salads'},
    {'label': 'breads', 'iconKey': 'bread'},
  ];

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      extendBody: true,
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          AppHeader(
            customContent: _buildSearchBox(context),
            onProfileTap: () => _showSettings(context),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 100),
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              AppTranslations.getText(ref, 'categories'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 28,
                                fontFamily: AppTheme.secondaryFontFamily,
                                color: AppTheme.textColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (user != null)
                            _buildDynamicCategoriesGrid(context, user.uid)
                          else
                            _buildDefaultCategoriesGrid(context),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }

  void _showSettings(BuildContext context) {
    final hostContext = context; // <-- stable parent context
    final isHebrew = ref.watch(settingsProvider).language == AppLanguage.hebrew;

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
                        child: SettingsMenu(
                          hostContext: hostContext,
                        ), // <-- pass it in
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
                      painter: WavyButtonPainter(),
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

  Widget _buildSearchBox(BuildContext context) {
    final isHebrew = ref.watch(settingsProvider).language == AppLanguage.hebrew;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child:
            isHebrew
                ? Stack(
                  children: [
                    // Hebrew: icon on the right using absolute positioning
                    TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppTheme.primaryColor,
                      ),
                      cursorColor: AppTheme.primaryColor,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.only(
                          left: 16,
                          right: 32, // Leave space for icon
                          top: 14,
                          bottom: 14,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: AppTranslations.getText(ref, 'search_hint'),
                        hintStyle: const TextStyle(
                          color: AppTheme.secondaryTextColor,
                          fontSize: 16,
                        ),
                      ),
                      onSubmitted: (value) {
                        if (value.trim().isNotEmpty) {
                          context.push('/search');
                        }
                      },
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 24,
                        alignment: Alignment.center,
                        child: SvgPicture.asset(
                          'assets/images/search.svg',
                          width: 20,
                          height: 20,
                          colorFilter: const ColorFilter.mode(
                            AppTheme.secondaryTextColor,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
                : Stack(
                  children: [
                    // English: icon on the left using absolute positioning
                    TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      textAlign: TextAlign.left,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppTheme.primaryColor,
                      ),
                      cursorColor: AppTheme.primaryColor,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.only(
                          left: 32, // Leave space for icon
                          right: 16,
                          top: 14,
                          bottom: 14,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: AppTranslations.getText(ref, 'search_hint'),
                        hintStyle: const TextStyle(
                          color: AppTheme.secondaryTextColor,
                          fontSize: 16,
                        ),
                      ),
                      onSubmitted: (value) {
                        if (value.trim().isNotEmpty) {
                          context.push('/search');
                        }
                      },
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 24,
                        alignment: Alignment.center,
                        child: SvgPicture.asset(
                          'assets/images/search.svg',
                          width: 20,
                          height: 20,
                          colorFilter: const ColorFilter.mode(
                            AppTheme.secondaryTextColor,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  Widget _buildDynamicCategoriesGrid(BuildContext context, String userId) {
    final categoriesAsync = ref.watch(userCategoriesProvider(userId));

    return categoriesAsync.when(
      data: (categories) {
        if (categories.isEmpty) {
          // Show default categories for new users
          return _buildDefaultCategoriesGrid(context);
        }
        return _buildCategoriesList(context, categories, true);
      },
      loading:
          () => const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
            ),
          ),
      error:
          (error, stack) => Center(
            child: Text(
              AppTranslations.getText(ref, 'error_loading_categories'),
              style: const TextStyle(
                color: AppTheme.textColor,
                fontFamily: AppTheme.secondaryFontFamily,
              ),
            ),
          ),
    );
  }

  Widget _buildDefaultCategoriesGrid(BuildContext context) {
    return _buildCategoriesList(context, _defaultCategories, false);
  }

  Widget _buildCategoriesList(
    BuildContext context,
    List<dynamic> categories,
    bool isDynamic,
  ) {
    // Calculate responsive sizes based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    // Make icons larger and cards visually tighter
    final iconSize = (screenWidth * 0.10).clamp(40.0, 72.0);
    final fontSize = (screenWidth * 0.033).clamp(12.0, 17.0);
    final spacing = (screenWidth * 0.06).clamp(12.0, 24.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, // more columns -> smaller cards
          childAspectRatio: 0.85,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
        ),
        itemCount: categories.length + 1, // +1 for add category button
        itemBuilder: (context, index) {
          if (index == categories.length) {
            // Add category button
            return GestureDetector(
              onTap: () => _showAddCategoryDialog(context),
              child: DottedBorderCard(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_outlined,
                        size: iconSize,
                        color: AppTheme.uiAccentColor,
                      ),
                      SizedBox(height: iconSize * 0.2),
                      Flexible(
                        child: Text(
                          AppTranslations.getText(ref, 'add_category'),
                          style: TextStyle(
                            fontSize: fontSize * 0.85, // Slightly smaller font
                            color: AppTheme.secondaryTextColor,
                            fontFamily: AppTheme.secondaryFontFamily,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final category = categories[index];
          final bool isSelected = selectedCategoryIndex == index;

          return GestureDetector(
            onTap: () {
              final String label =
                  isDynamic ? category.name : category['label'] as String;
              final String categoryId = isDynamic ? category.id : '';
              setState(() {
                selectedCategoryIndex = index;
              });
              context.push('/category/$label/$categoryId');
            },
            onLongPress:
                isDynamic
                    ? () {
                      _showCategoryContextMenu(context, category);
                    }
                    : null,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(12),
                border:
                    isSelected
                        ? Border.all(color: AppTheme.primaryColor, width: 2)
                        : null,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.dividerColor.withValues(alpha: 0.04),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    isDynamic
                        ? CategoryIconService.getIconByKey(
                          category.icon,
                          size: iconSize,
                          color: AppTheme.primaryColor,
                        )
                        : CategoryIconService.getIconByKey(
                          category['iconKey'] as String,
                          size: iconSize,
                          color: AppTheme.primaryColor,
                        ),
                    SizedBox(height: iconSize * 0.1),
                    Text(
                      isDynamic
                          ? category.name
                          : AppTranslations.getText(
                            ref,
                            category['label'] as String,
                          ),
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textColor,
                        fontFamily: AppTheme.secondaryFontFamily,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddCategoryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const AddCategoryDialog(),
    );
  }

  void _showEditCategoryDialog(BuildContext context, Category category) {
    showDialog(
      context: context,
      builder: (context) => AddCategoryDialog(categoryToEdit: category),
    );
  }

  void _showCategoryContextMenu(BuildContext context, Category category) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            decoration: const BoxDecoration(
              color: AppTheme.backgroundColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryTextColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.edit, color: AppTheme.primaryColor),
                  title: Text(AppTranslations.getText(ref, 'edit_category')),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditCategoryDialog(context, category);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: AppTheme.errorColor),
                  title: Text(AppTranslations.getText(ref, 'delete_category')),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteCategoryConfirmation(context, category);
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
    );
  }

  void _showDeleteCategoryConfirmation(
    BuildContext context,
    Category category,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(AppTranslations.getText(ref, 'delete_category')),
            content: Text(
              AppTranslations.getText(ref, 'delete_category_confirmation'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppTranslations.getText(ref, 'cancel')),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  try {
                    final categoryService = ref.read(categoryServiceProvider);
                    await categoryService.deleteCategory(category.id);
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            AppTranslations.getText(
                              ref,
                              'category_deleted_successfully',
                            ),
                          ),
                          backgroundColor: AppTheme.successColor,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            AppTranslations.getText(
                              ref,
                              'error_deleting_category',
                            ).replaceAll('{error}', e.toString()),
                          ),
                          backgroundColor: AppTheme.errorColor,
                        ),
                      );
                    }
                  }
                },
                child: Text(
                  AppTranslations.getText(ref, 'delete'),
                  style: const TextStyle(color: AppTheme.errorColor),
                ),
              ),
            ],
          ),
    );
  }
}

// Dotted border card for add-category
class DottedBorderCard extends StatelessWidget {
  final Widget child;
  const DottedBorderCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint =
        Paint()
          ..color = AppTheme.uiAccentColor
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
    const double dashWidth = 6.0;
    const double dashSpace = 4.0;
    final RRect rRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(12),
    );
    final Path path = Path()..addRRect(rRect);
    double distance = 0.0;
    final PathMetrics pathMetrics = path.computeMetrics();
    for (final PathMetric pathMetric in pathMetrics) {
      while (distance < pathMetric.length) {
        final double nextDash = distance + dashWidth;
        final bool isDashEnd = nextDash < pathMetric.length;
        final Path extractPath = pathMetric.extractPath(
          distance,
          isDashEnd ? nextDash : pathMetric.length,
        );
        canvas.drawPath(extractPath, paint);
        distance += dashWidth + dashSpace;
      }
      distance = 0.0;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class WavyButtonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = AppTheme.uiAccentColor
          ..style = PaintingStyle.fill;

    final path = Path();

    // Start from top-left
    path.moveTo(0, 0);

    // Create concave curve on the left edge
    path.cubicTo(
      size.width * 0.1,
      size.height * 0.2, // Control point 1
      size.width * 0.1,
      size.height * 0.8, // Control point 2
      0,
      size.height, // End at bottom-left
    );

    // Bottom edge (straight)
    path.lineTo(size.width, size.height);

    // Right edge (straight)
    path.lineTo(size.width, 0);

    // Top edge (straight)
    path.lineTo(0, 0);

    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
