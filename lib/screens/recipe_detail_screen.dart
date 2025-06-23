import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/helpers.dart';
import 'package:recipe_keeper/models/recipe.dart';
import 'package:recipe_keeper/providers/recipe_provider.dart'
    as recipe_providers;
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:recipe_keeper/services/image_service.dart';
import 'package:url_launcher/url_launcher.dart';

class RecipeDetailScreen extends ConsumerStatefulWidget {
  final String recipeId;

  const RecipeDetailScreen({super.key, required this.recipeId});

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final recipeAsync = ref.watch(
      recipe_providers.recipeProvider(widget.recipeId),
    );
    final userData = ref.watch(userDataProvider).value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final double statusBarHeight = mediaQuery.padding.top;
    final double appBarHeight = AppBar().preferredSize.height;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (recipeAsync.value != null)
            _buildFavoriteButton(recipeAsync.value!),
          // Only show the edit/delete menu if it's the user's own recipe.
          if (userData != null &&
              recipeAsync.value != null &&
              recipeAsync.value!.userId == userData.id)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                if (value == 'edit') {
                  context.push('/edit-recipe/${recipeAsync.value!.id}');
                } else if (value == 'delete') {
                  _showDeleteConfirmation(context, recipeAsync.value!, ref);
                }
              },
              itemBuilder:
                  (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          const Icon(Icons.edit, color: AppTheme.primaryColor),
                          const SizedBox(width: 8),
                          Text(AppTranslations.getText(ref, 'edit_recipe')),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete, color: Colors.red),
                          const SizedBox(width: 8),
                          Text(
                            AppTranslations.getText(ref, 'delete_recipe'),
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
            ),
        ],
      ),
      body: recipeAsync.when(
        data: (recipe) {
          if (recipe == null) {
            return const Center(child: Text('Recipe not found'));
          }

          // Design parameters for layout.
          final double imageHeight = 300 + statusBarHeight;
          final double cardHeight = 180; // Increased height for better content
          final double screenWidth = MediaQuery.of(context).size.width;
          final double cardWidth =
              screenWidth * 0.85; // Wider card for better readability
          final double halfCardHeight = cardHeight / 2;

          return SingleChildScrollView(
            child: Stack(
              children: [
                // Main column with the recipe image and content.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Recipe image container.
                    SizedBox(
                      height: imageHeight,
                      width: double.infinity,
                      child: Stack(
                        children: [
                          // Image or placeholder
                          Positioned.fill(
                            child:
                                recipe.imageUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                      imageUrl: ImageService()
                                          .getCorsProxiedUrl(recipe.imageUrl),
                                      fit: BoxFit.cover,
                                      placeholder:
                                          (context, url) => const Center(
                                            child: CircularProgressIndicator(
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                      errorWidget: (context, url, error) {
                                        return Container(
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
                                        );
                                      },
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
                          // Enhanced gradient overlay for better text visibility
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: statusBarHeight + appBarHeight,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.8),
                                    Colors.black.withOpacity(0.4),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Add space equal to half the card's height.
                    SizedBox(height: cardHeight / 2),
                    // The rest of the page content.
                    Container(
                      decoration: BoxDecoration(
                        color:
                            isDark
                                ? AppTheme.darkBackgroundColor
                                : Colors.white,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Recipe content sections
                          _buildRecipeContent(context, recipe, isDark, ref),
                        ],
                      ),
                    ),
                  ],
                ),
                // Overlapping info card (half above the image bottom, half below).
                Positioned(
                  top: imageHeight - (cardHeight / 2),
                  left: (screenWidth - cardWidth) / 2,
                  child: Container(
                    width: cardWidth,
                    height: cardHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.4 : 0.15),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Column(
                        children: [
                          // Blue top half
                          Container(
                            width: double.infinity,
                            height: halfCardHeight,
                            color: AppTheme.primaryColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            child:
                                recipe.description.isNotEmpty
                                    ? Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        // Recipe Title
                                        Text(
                                          recipe.title,
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 6),
                                        // Description
                                        Text(
                                          recipe.description,
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 14,
                                            color: Colors.white,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    )
                                    : Center(
                                      child: Text(
                                        recipe.title,
                                        style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                          ),
                          // White bottom half
                          Container(
                            width: double.infinity,
                            height: halfCardHeight,
                            color:
                                isDark ? AppTheme.darkCardColor : Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Center(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildStatItem(
                                    icon: Icons.star_rounded,
                                    value: '4.3',
                                    label: AppTranslations.getText(
                                      ref,
                                      'rating',
                                    ),
                                    color: Colors.amber[800],
                                    isDark: isDark,
                                    ref: ref,
                                  ),
                                  _buildStatItem(
                                    icon: Icons.schedule,
                                    value: Helpers.formatCookingTimeWithRef(
                                      recipe.prepTime + recipe.cookTime,
                                      ref,
                                    ),
                                    label: AppTranslations.getText(
                                      ref,
                                      'total_time',
                                    ),
                                    isDark: isDark,
                                    ref: ref,
                                  ),
                                  _buildDifficultyItem(
                                    value: AppTranslations.getText(ref, 'easy'),
                                    label: AppTranslations.getText(
                                      ref,
                                      'difficulty',
                                    ),
                                    isDark: isDark,
                                    ref: ref,
                                  ),
                                  if (recipe.servings > 0)
                                    _buildStatItem(
                                      icon: Icons.people_outline,
                                      value: '${recipe.servings}',
                                      label: AppTranslations.getText(
                                        ref,
                                        'servings',
                                      ),
                                      isDark: isDark,
                                      ref: ref,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, stackTrace) =>
                Center(child: Text('Error: ${error.toString()}')),
      ),
      floatingActionButton:
          recipeAsync.value != null &&
                  userData != null &&
                  recipeAsync.value!.userId == userData.id
              ? FloatingActionButton(
                onPressed: () {
                  context.push('/edit-recipe/${widget.recipeId}');
                },
                child: const Icon(Icons.edit),
              )
              : null,
    );
  }

  // Main method to build all recipe content sections
  Widget _buildRecipeContent(
    BuildContext context,
    Recipe recipe,
    bool isDark,
    WidgetRef ref,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Source URL Section
        if (recipe.sourceUrl.isNotEmpty)
          _buildSection(
            title: AppTranslations.getText(ref, 'source'),
            isDark: isDark,
            context: context,
            child: GestureDetector(
              onTap: () async {
                final Uri url = Uri.parse(recipe.sourceUrl);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppTranslations.getText(ref, 'could_not_launch_url'),
                        ),
                      ),
                    );
                  }
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.primaryColor.withOpacity(0.15),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        recipe.sourceUrl,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          color: AppTheme.primaryColor,
                          decoration: TextDecoration.underline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Ingredients Section
        if (recipe.ingredients.isNotEmpty)
          _buildSection(
            title: AppTranslations.getText(ref, 'ingredients'),
            isDark: isDark,
            context: context,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recipe.ingredients.length,
              separatorBuilder:
                  (_, __) => SizedBox(
                    height: MediaQuery.of(context).size.height * 0.015,
                  ),
              itemBuilder: (context, index) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.fiber_manual_record,
                        size: 8,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        recipe.ingredients[index],
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          color:
                              isDark
                                  ? AppTheme.darkTextColor
                                  : AppTheme.textColor,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

        // Instructions Section
        if (recipe.instructions.isNotEmpty)
          _buildSection(
            title: AppTranslations.getText(ref, 'instructions'),
            isDark: isDark,
            context: context,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recipe.instructions.length,
              separatorBuilder:
                  (_, __) => SizedBox(
                    height: MediaQuery.of(context).size.height * 0.025,
                  ),
              itemBuilder: (context, index) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.primaryColor,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        recipe.instructions[index],
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          color:
                              isDark
                                  ? AppTheme.darkTextColor
                                  : AppTheme.textColor,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

        // Notes Section
        if (recipe.notes.isNotEmpty)
          _buildSection(
            title: AppTranslations.getText(ref, 'notes'),
            isDark: isDark,
            context: context,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.primaryColor.withOpacity(0.15),
                ),
              ),
              child: Text(
                recipe.notes,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  color: isDark ? AppTheme.darkTextColor : AppTheme.textColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),

        // Tags Section
        if (recipe.tags.isNotEmpty)
          _buildSection(
            title: AppTranslations.getText(ref, 'tags'),
            isDark: isDark,
            context: context,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children:
                  recipe.tags.map((tag) {
                    return Chip(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      labelPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: -2,
                      ),
                      label: Text(
                        tag,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                    );
                  }).toList(),
            ),
          ),

        // Source Section (Modified)
        if (recipe.source.isNotEmpty)
          _buildSection(
            title: AppTranslations.getText(ref, 'source'),
            isDark: isDark,
            context: context,
            child: InkWell(
              // Make the source tappable
              onTap: () async {
                final Uri? uri = Uri.tryParse(recipe.source);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${AppTranslations.getText(ref, 'cannot_launch_url')}: ${recipe.source}',
                        ),
                      ),
                    );
                  }
                  print('Could not launch ${recipe.source}');
                }
              },
              child: Text(
                recipe.source,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  color: AppTheme.primaryColor, // Keep link color
                  decoration: TextDecoration.underline,
                  decorationColor: AppTheme.primaryColor, // Underline color
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Reusable section builder with consistent spacing
  Widget _buildSection({
    required String title,
    required bool isDark,
    required BuildContext context,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.darkTextColor : AppTheme.textColor,
            ),
          ),
          const SizedBox(height: 16),
          child,
          const Divider(height: 32),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    Color? color,
    required bool isDark,
    required WidgetRef ref,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: color ?? (isDark ? Colors.white : Colors.black),
            ),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color ?? (isDark ? Colors.white : Colors.black),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            color: isDark ? Colors.grey[300] : Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _buildDifficultyItem({
    required String value,
    required String label,
    required bool isDark,
    required WidgetRef ref,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.blue,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            color: isDark ? Colors.grey[300] : Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _buildFavoriteButton(Recipe recipe) {
    return Consumer(
      builder: (context, ref, child) {
        // Use the top-level providers from recipe_provider.dart
        final isFavorite = ref.watch(
          recipe_providers.recipeFavoriteStatusProvider(recipe.id),
        );
        final recipeNotifier = ref.read(
          recipe_providers.recipeStateProvider.notifier,
        );

        return IconButton(
          icon: Icon(
            isFavorite ? Icons.favorite : Icons.favorite_border,
            color: isFavorite ? Colors.red : null,
          ),
          onPressed: () {
            recipeNotifier.toggleFavorite(recipe);
          },
        );
      },
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    Recipe recipe,
    WidgetRef ref,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(AppTranslations.getText(ref, 'delete_recipe_title')),
            content: Text(
              AppTranslations.getText(
                ref,
                'delete_recipe_confirmation',
              ).replaceAll('{recipe}', recipe.title),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(AppTranslations.getText(ref, 'cancel')),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  ref
                      .read(recipe_providers.recipeStateProvider.notifier)
                      .deleteRecipe(recipe.id);
                  context.go('/home');
                },
                child: Text(
                  AppTranslations.getText(ref, 'delete'),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }
}
