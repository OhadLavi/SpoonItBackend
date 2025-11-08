import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spoonit/services/category_service.dart';
import 'package:spoonit/models/category.dart';
import 'package:spoonit/widgets/app_header.dart';
import 'package:spoonit/widgets/app_bottom_nav.dart';
import 'package:spoonit/widgets/add_category_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/services/category_icon_service.dart';
import 'package:spoonit/utils/translations.dart';
import 'package:spoonit/utils/responsive_utils.dart';
import 'package:spoonit/utils/navigation_helpers.dart';
import 'package:spoonit/widgets/common/dotted_border_card.dart';
import 'package:spoonit/widgets/common/directional_text.dart';
import 'package:spoonit/widgets/forms/app_text_field.dart';
import 'package:spoonit/widgets/forms/app_form_container.dart';
import 'package:spoonit/widgets/feedback/app_loading_indicator.dart';

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
  bool _hasUserInteracted = false;

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
  void initState() {
    super.initState();
    // Listen to focus changes to reset interaction flag
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) {
        // Reset flag when field loses focus
        _hasUserInteracted = false;
      }
    });
    // Unfocus search field when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_searchFocusNode.hasFocus && !_hasUserInteracted) {
        _searchFocusNode.unfocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    // Unfocus search field when navigating back to home screen
    // Only if user hasn't intentionally focused it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchFocusNode.hasFocus && !_hasUserInteracted) {
        _searchFocusNode.unfocus();
      }
    });

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
    NavigationHelpers.showSettingsPanel(context, ref);
  }

  Widget _buildSearchBox(BuildContext context) {
    return AppFormContainer(
      child: AppTextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        hintText: AppTranslations.getText(ref, 'search_hint'),
        prefixSvgAsset: 'assets/images/search.svg',
        textInputAction: TextInputAction.search,
        onTap: () {
          _hasUserInteracted = true;
        },
        onFieldSubmitted: (value) {
          if (value.trim().isNotEmpty) {
            // Navigate to search screen with the query
            context.push('/search?q=${Uri.encodeComponent(value.trim())}');
          }
        },
        suffixIcon: IconButton(
          icon: const Icon(
            Icons.search,
            color: AppTheme.primaryColor,
          ),
          onPressed: () {
            final query = _searchController.text.trim();
            if (query.isNotEmpty) {
              context.push('/search?q=${Uri.encodeComponent(query)}');
            } else {
              context.push('/search');
            }
          },
          iconSize: 20,
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
      loading: () => const Center(child: AppLoadingIndicator()),
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
    // Calculate responsive sizes using utilities
    final iconSize = ResponsiveUtils.calculateResponsiveIconSize(
      context,
      minSize: 40.0,
      maxSize: 72.0,
      scaleFactor: 0.10,
    );
    final fontSize = ResponsiveUtils.calculateResponsiveFontSize(
      context,
      minSize: 12.0,
      maxSize: 17.0,
      scaleFactor: 0.033,
    );
    final spacing = ResponsiveUtils.calculateResponsiveSpacing(
      context,
      minSpacing: 12.0,
      maxSpacing: 24.0,
      scaleFactor: 0.06,
    );

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
                        child: DirectionalText(
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
                    DirectionalText(
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
