import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
// import 'package:recipe_keeper/utils/helpers.dart';
// import 'package:recipe_keeper/models/recipe.dart';
import 'package:recipe_keeper/providers/recipe_provider.dart'
    as recipe_providers;
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:recipe_keeper/services/image_service.dart';
// import 'package:url_launcher/url_launcher.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';
import 'package:share_plus/share_plus.dart';
import 'package:recipe_keeper/services/shopping_list_service.dart';

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
        color: AppTheme.primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15)),
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
                                                .withOpacity(0.1),
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
                                      color: AppTheme.primaryColor.withOpacity(
                                        0.1,
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
                                  (_, __) => const SizedBox(height: 8),
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
                                color: AppTheme.primaryColor.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppTheme.primaryColor.withOpacity(
                                    0.15,
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

                        const SizedBox(height: 24),
                        Center(
                          child: Text(
                            AppTranslations.getText(ref, 'bon_appetit'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
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
              loading:
                  () => const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                    ),
                  ),
              error:
                  (error, stackTrace) =>
                      Center(child: Text('Error: ${error.toString()}')),
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
        separatorBuilder: (_, __) => const SizedBox(height: 10),
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
    Share.share(shareText);
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
              style: TextStyle(fontFamily: AppTheme.primaryFontFamily),
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
                style: TextStyle(fontFamily: AppTheme.primaryFontFamily),
              ),
              backgroundColor: AppTheme.primaryColor.withOpacity(0.8),
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
              style: TextStyle(fontFamily: AppTheme.primaryFontFamily),
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
          backgroundColor = AppTheme.primaryColor.withOpacity(0.8);
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
}
