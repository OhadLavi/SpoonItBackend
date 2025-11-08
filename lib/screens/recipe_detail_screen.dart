import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spoonit/utils/app_theme.dart';
// import 'package:spoonit/utils/helpers.dart';
// import 'package:spoonit/models/recipe.dart';
import 'package:spoonit/providers/recipe_provider.dart' as recipe_providers;
import 'package:spoonit/providers/auth_provider.dart';
import 'package:spoonit/utils/translations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spoonit/services/image_service.dart';
import 'package:spoonit/utils/language_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:spoonit/widgets/app_bottom_nav.dart';
import 'package:share_plus/share_plus.dart';
import 'package:spoonit/services/shopping_list_service.dart';
import 'package:spoonit/widgets/feedback/app_loading_indicator.dart';
import 'package:spoonit/widgets/feedback/app_error_container.dart';

class RecipeDetailScreen extends ConsumerStatefulWidget {
  final String recipeId;

  const RecipeDetailScreen({super.key, required this.recipeId});

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  int _lastCompletedStep = -1;
  final ShoppingListService _shoppingListService = ShoppingListService();

  Widget _detailTile(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.15),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: AppTheme.primaryFontFamily,
          fontSize: 14,
          color: AppTheme.recipeTextColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipeAsync = ref.watch(
      recipe_providers.recipeProvider(widget.recipeId),
    );
    final userData = ref.watch(userDataProvider).value;

    return Scaffold(
      extendBody: true,
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          // Header removed per design
          Expanded(
            child: recipeAsync.when(
              data: (recipe) {
                if (recipe == null) {
                  return const Center(child: Text('Recipe not found'));
                }

                final sourceLink = _getRecipeSourceLink(recipe);
                final isHebrew = LanguageUtils.isHebrew(ref);
                return ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Top image - full width, no padding
                        ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(24),
                            bottomRight: Radius.circular(24),
                          ),
                          child: SizedBox(
                            height: 240,
                            child:
                                recipe.imageUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                      imageUrl: ImageService()
                                          .getCorsProxiedUrl(recipe.imageUrl),
                                      fit: BoxFit.contain,
                                      placeholder:
                                          (context, url) => const Center(
                                            child: CircularProgressIndicator(
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                      errorWidget:
                                          (context, url, error) => Container(
                                            color: AppTheme.primaryColor
                                                .withValues(alpha: 0.1),
                                            child: const Center(
                                              child: Icon(
                                                Icons
                                                    .image_not_supported_outlined,
                                                color: AppTheme.primaryColor,
                                                size: 48,
                                              ),
                                            ),
                                          ),
                                    )
                                    : Container(
                                      color: AppTheme.primaryColor.withValues(
                                        alpha: 0.1,
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.restaurant_menu,
                                          color: AppTheme.primaryColor,
                                          size: 48,
                                        ),
                                      ),
                                    ),
                          ),
                        ),

                        // Title and actions - with consistent padding
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    recipe.title,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontFamily: AppTheme.primaryFontFamily,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textColor,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              // Share button for all users
                              IconButton(
                                icon: const Icon(
                                  Icons.share,
                                  color: AppTheme.secondaryTextColor,
                                ),
                                onPressed: () => _shareRecipe(recipe),
                              ),
                              // Edit button only for recipe owner
                              if (userData != null &&
                                  recipe.userId == userData.id)
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: AppTheme.textColor,
                                  ),
                                  onPressed:
                                      () => context.push(
                                        '/edit-recipe/${recipe.id}',
                                      ),
                                ),
                            ],
                          ),
                        ),

                        // Cooking details - each in its own peach tile, same row
                        if (recipe.prepTime > 0 ||
                            recipe.cookTime > 0 ||
                            recipe.servings > 0)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Directionality(
                              textDirection: TextDirection.rtl,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  if (recipe.prepTime > 0)
                                    _detailTile(
                                      AppTranslations.getText(
                                        ref,
                                        'prep_time_minutes',
                                      ).replaceAll(
                                        '{time}',
                                        recipe.prepTime.toString(),
                                      ),
                                    ),
                                  if (recipe.cookTime > 0) ...[
                                    const SizedBox(width: 10),
                                    _detailTile(
                                      AppTranslations.getText(
                                        ref,
                                        'cook_time_minutes',
                                      ).replaceAll(
                                        '{time}',
                                        recipe.cookTime.toString(),
                                      ),
                                    ),
                                  ],
                                  if (recipe.servings > 0) ...[
                                    const SizedBox(width: 10),
                                    _detailTile(
                                      AppTranslations.getText(
                                        ref,
                                        'servings_count',
                                      ).replaceAll(
                                        '{count}',
                                        recipe.servings.toString(),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                        // Ingredients
                        _buildSection(
                          title: AppTranslations.getText(ref, 'ingredients'),
                          context: context,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: recipe.ingredients.length,
                              separatorBuilder:
                                  (ctx, idx) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                return GestureDetector(
                                  onLongPress:
                                      () => _addIngredientToShoppingList(
                                        recipe.ingredients[index],
                                        userData?.uid,
                                      ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(top: 6),
                                        child: Icon(
                                          Icons.fiber_manual_record,
                                          size: 6,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          child: Text(
                                            recipe.ingredients[index],
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(
                                              fontFamily:
                                                  AppTheme.primaryFontFamily,
                                              fontSize: 15,
                                              color: AppTheme.recipeTextColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // Instructions progressive
                        if (recipe.instructions.isNotEmpty)
                          _buildSection(
                            title: AppTranslations.getText(ref, 'instructions'),
                            context: context,
                            child: _buildInstructionList(
                              context,
                              recipe.instructions,
                            ),
                          ),

                        // Tags
                        if (recipe.tags.isNotEmpty)
                          _buildSection(
                            title: AppTranslations.getText(ref, 'tags'),
                            context: context,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children:
                                    recipe.tags
                                        .map(
                                          (tag) => Chip(
                                            label: Text(
                                              tag,
                                              style: const TextStyle(
                                                color: AppTheme.textColor,
                                                fontFamily:
                                                    AppTheme.primaryFontFamily,
                                              ),
                                            ),
                                            backgroundColor: const Color(
                                              0xFFFFF0EE,
                                            ),
                                            deleteIconColor: const Color(
                                              0xFFFF7E6B,
                                            ),
                                          ),
                                        )
                                        .toList(),
                              ),
                            ),
                          ),

                        // Notes
                        if (recipe.notes.isNotEmpty)
                          _buildSection(
                            title: AppTranslations.getText(ref, 'notes'),
                            context: context,
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(left: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.05,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.15,
                                  ),
                                ),
                              ),
                              child: Text(
                                recipe.notes,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontFamily: AppTheme.primaryFontFamily,
                                  fontSize: 15,
                                  color: AppTheme.recipeTextColor,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),
// Source link
if (sourceLink.isNotEmpty)
  Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openSourceUrl(sourceLink),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Directionality(
            textDirection:
                isHebrew ? TextDirection.ltr : TextDirection.rtl,
            child: isHebrew
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // icon on the right (because RTL)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.link,
                          color: AppTheme.primaryColor,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // text block, right aligned
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AppTranslations.getText(
                                ref,
                                'recipe_source',
                              ),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontFamily: AppTheme.primaryFontFamily,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textColor,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _formatUrl(sourceLink, showFull: true),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontFamily: AppTheme.secondaryFontFamily,
                                fontSize: 13,
                                color: AppTheme.secondaryTextColor,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              // URL itself should stay LTR even in RTL
                              textDirection: TextDirection.ltr,
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(
                        Icons.open_in_new,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppTranslations.getText(
                                  ref,
                                  'recipe_source',
                                ),
                                style: const TextStyle(
                                  fontFamily: AppTheme.primaryFontFamily,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatUrl(sourceLink),
                                style: const TextStyle(
                                  fontFamily: AppTheme.secondaryFontFamily,
                                  fontSize: 12,
                                  color: AppTheme.secondaryTextColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.link,
                        color: AppTheme.primaryColor,
                        size: 24,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ),
  ),


                        const SizedBox(height: 24),
                        Center(
                          child: Text(
                            AppTranslations.getText(ref, 'bon_appetit'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: AppTheme.primaryFontFamily,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 45),
                      ],
                    ),
                  ),
                );
              },
              loading: () => const Center(child: AppLoadingIndicator()),
              error:
                  (error, stackTrace) => Center(
                    child: AppErrorContainer(
                      message: 'Error: ${error.toString()}',
                    ),
                  ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: -1),
    );
  }

  // Removed legacy builder (intentionally left out)

  Widget _buildInstructionList(BuildContext context, List<String> steps) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: steps.length,
        separatorBuilder: (ctx, idx) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final bool enabled = index <= _lastCompletedStep + 1;
          final bool checked = index <= _lastCompletedStep;
          final bool isNextStep = index == _lastCompletedStep + 1;

          final TextStyle baseStyle = TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            fontSize: 15,
            color:
                enabled
                    ? AppTheme.recipeTextColor
                    : AppTheme.secondaryTextColor,
            fontWeight: isNextStep ? FontWeight.w600 : FontWeight.w400,
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                value: checked,
                onChanged:
                    enabled
                        ? (value) {
                          setState(() {
                            if (value == true &&
                                index == _lastCompletedStep + 1) {
                              _lastCompletedStep = index;
                            } else if (value == false &&
                                index == _lastCompletedStep) {
                              _lastCompletedStep = index - 1;
                            }
                          });
                        }
                        : null,
                activeColor: AppTheme.primaryColor,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    steps[index],
                    style: baseStyle,
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Reusable section builder with consistent spacing
  Widget _buildSection({
    required String title,
    required BuildContext context,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(
              title,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppTheme.textColor,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(padding: const EdgeInsets.only(right: 16), child: child),
        ],
      ),
    );
  }

  // Share recipe functionality
  void _shareRecipe(dynamic recipe) {
    final String shareText = _buildShareText(recipe);
    // Share the recipe using the updated SharePlus API
    SharePlus.instance.share(ShareParams(text: shareText, subject: 'Recipe'));
  }

  String _buildShareText(dynamic recipe) {
    final StringBuffer shareText = StringBuffer();

    // Recipe title
    shareText.writeln('🍽️ ${recipe.title}');
    shareText.writeln();

    // Cooking details
    if (recipe.prepTime > 0 || recipe.cookTime > 0 || recipe.servings > 0) {
      shareText.writeln('⏱️ ${AppTranslations.getText(ref, 'details')}:');
      if (recipe.prepTime > 0) {
        shareText.writeln(
          AppTranslations.getText(
            ref,
            'prep_time_minutes',
          ).replaceAll('{time}', recipe.prepTime.toString()),
        );
      }
      if (recipe.cookTime > 0) {
        shareText.writeln(
          AppTranslations.getText(
            ref,
            'cook_time_minutes',
          ).replaceAll('{time}', recipe.cookTime.toString()),
        );
      }
      if (recipe.servings > 0) {
        shareText.writeln(
          AppTranslations.getText(
            ref,
            'servings_count',
          ).replaceAll('{count}', recipe.servings.toString()),
        );
      }
      shareText.writeln();
    }

    // Ingredients
    if (recipe.ingredients.isNotEmpty) {
      shareText.writeln(
        '🥘 ${AppTranslations.getText(ref, 'ingredients_section')}:',
      );
      for (int i = 0; i < recipe.ingredients.length; i++) {
        shareText.writeln('${i + 1}. ${recipe.ingredients[i]}');
      }
      shareText.writeln();
    }

    // Instructions
    if (recipe.instructions.isNotEmpty) {
      shareText.writeln(
        '👨‍🍳 ${AppTranslations.getText(ref, 'instructions_section')}:',
      );
      for (int i = 0; i < recipe.instructions.length; i++) {
        shareText.writeln('${i + 1}. ${recipe.instructions[i]}');
      }
      shareText.writeln();
    }

    // Notes
    if (recipe.notes.isNotEmpty) {
      shareText.writeln('📝 ${AppTranslations.getText(ref, 'notes_section')}:');
      shareText.writeln(recipe.notes);
      shareText.writeln();
    }

    // Tags
    if (recipe.tags.isNotEmpty) {
      shareText.writeln(
        '🏷️ ${AppTranslations.getText(ref, 'tags_section')}: ${recipe.tags.join(', ')}',
      );
      shareText.writeln();
    }

    shareText.writeln('${AppTranslations.getText(ref, 'bon_appetit')} 🍽️');
    shareText.writeln();
    shareText.writeln(
      AppTranslations.getText(ref, 'shared_from_recipe_keeper'),
    );

    return shareText.toString();
  }

  // Favorite button removed per design

  // Add ingredient to shopping list
  Future<void> _addIngredientToShoppingList(
    String ingredient,
    String? userId,
  ) async {
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'login_to_add_to_shopping_list'),
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
            ),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
      return;
    }

    try {
      // Check if item already exists
      final exists = await _shoppingListService.itemExists(userId, ingredient);

      if (exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppTranslations.getText(ref, 'item_already_in_shopping_list'),
                textAlign: TextAlign.right,
                style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
              ),
              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.8),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Add to shopping list
      await _shoppingListService.addItem(userId, ingredient);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'item_added_to_shopping_list'),
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
            ),
            backgroundColor: AppTheme.primaryColor,
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: AppTranslations.getText(ref, 'to_list'),
              textColor: AppTheme.lightAccentColor,
              onPressed: () {
                context.go('/shopping-list');
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage;
        Color backgroundColor;

        if (e.toString().contains('Shopping list limit reached')) {
          errorMessage = AppTranslations.getText(ref, 'shopping_list_full');
          backgroundColor = AppTheme.warningColor;
        } else if (e.toString().contains('Item already exists')) {
          errorMessage = AppTranslations.getText(
            ref,
            'item_already_in_shopping_list',
          );
          backgroundColor = AppTheme.primaryColor.withValues(alpha: 0.8);
        } else {
          errorMessage = AppTranslations.getText(
            ref,
            'error_adding_item',
          ).replaceAll('{error}', e.toString());
          backgroundColor = AppTheme.errorColor;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
            ),
            backgroundColor: backgroundColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Open source URL in browser
  Future<void> _openSourceUrl(String url) async {
    final uri = _normalizeUrlForLaunch(url);
    if (uri == null) {
      _showCannotOpenUrl();
      return;
    }

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showCannotOpenUrl();
      }
    } catch (_) {
      _showCannotOpenUrl();
    }
  }

  void _showCannotOpenUrl() {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppTranslations.getText(ref, 'cannot_open_url'),
          textAlign: TextAlign.right,
          style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
        ),
        backgroundColor: AppTheme.errorColor,
      ),
    );
  }

  // Format URL for display (remove protocol, truncate if needed)
  String _formatUrl(String url, {bool showFull = false}) {
    final uri = _normalizeUrlForLaunch(url);

    if (uri == null) {
      final trimmed = url.trim();
      if (showFull || trimmed.length <= 50) {
        return trimmed;
      }
      return '${trimmed.substring(0, 47)}...';
    }

    if (showFull) {
      // For full display, show www + domain + path but decode properly
      var fullUrl = uri.host;
      // Add www if not present
      if (!fullUrl.startsWith('www.')) {
        fullUrl = 'www.$fullUrl';
      }
      if (uri.path.isNotEmpty && uri.path != '/') {
        // Decode the path for better readability
        fullUrl += Uri.decodeComponent(uri.path);
      }
      return fullUrl;
    }

    // For compact display, show just domain or domain + short path
    var display = uri.host;
    if (uri.path.isNotEmpty && uri.path != '/') {
      // Only show path if it's short enough
      final decodedPath = Uri.decodeComponent(uri.path);
      if (decodedPath.length <= 30) {
        display += decodedPath;
      } else {
        // Show first part of path
        display += '${decodedPath.substring(0, 27)}...';
      }
    }

    if (display.length > 60) {
      display = '${display.substring(0, 57)}...';
    }
    return display;
  }

  Uri? _normalizeUrlForLaunch(String url) {
    var trimmed = url.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (!trimmed.startsWith(RegExp(r'https?://', caseSensitive: false))) {
      trimmed = 'https://$trimmed';
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }

    return uri;
  }

  String _getRecipeSourceLink(dynamic recipe) {
    final sourceUrl = (recipe.sourceUrl ?? '').toString().trim();
    if (_normalizeUrlForLaunch(sourceUrl) != null) {
      return sourceUrl;
    }

    final source = (recipe.source ?? '').toString().trim();
    if (_normalizeUrlForLaunch(source) != null) {
      return source;
    }

    return '';
  }
}
