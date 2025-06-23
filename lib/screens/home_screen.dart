import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/helpers.dart';
import 'package:recipe_keeper/providers/auth_provider.dart' as auth;
import 'package:recipe_keeper/providers/recipe_provider.dart';
import 'package:recipe_keeper/models/recipe.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:recipe_keeper/widgets/recipe_card.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:recipe_keeper/services/image_service.dart';
import 'package:recipe_keeper/models/app_user.dart';

final gridViewProvider = StateProvider<bool>((ref) => false);
final favoritesUIProvider = StateProvider<Set<String>>((ref) => <String>{});

class HomeScreen extends ConsumerStatefulWidget {
  final Widget child;

  const HomeScreen({super.key, required this.child});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder:
          (context, ref, _) => Scaffold(
            body: widget.child,
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerDocked,
            floatingActionButton: SizedBox(
              height: 70,
              width: 70,
              child: FloatingActionButton(
                onPressed: () => _showAddRecipeOptions(context),
                backgroundColor: AppTheme.primaryColor,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(35),
                ),
                child: const Icon(Icons.add, size: 38),
              ),
            ),
            bottomNavigationBar: BottomAppBar(
              shape: const CircularNotchedRectangle(),
              notchMargin: 12,
              height: 80,
              padding: EdgeInsets.zero,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: _buildNavItem(
                      ref,
                      0,
                      Icons.home_outlined,
                      Icons.home,
                      'home',
                      context,
                    ),
                  ),
                  Expanded(
                    child: _buildNavItem(
                      ref,
                      1,
                      Icons.favorite_border_outlined,
                      Icons.favorite,
                      'favorites',
                      context,
                    ),
                  ),
                  Expanded(
                    child: _buildNavItem(
                      ref,
                      2,
                      Icons.auto_fix_high, // new icon for custom recipe page
                      Icons.auto_fix_high,
                      'custom_recipe',
                      context,
                    ),
                  ),
                  Expanded(
                    child: _buildNavItem(
                      ref,
                      3,
                      Icons.person_outline,
                      Icons.person,
                      'profile',
                      context,
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  int _getSelectedIndex(String location) {
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/favorites')) return 1;
    if (location.startsWith('/custom_recipe')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/favorites');
        break;
      case 2:
        context.go('/custom_recipe');
        break;
      case 3:
        context.go('/profile');
        break;
    }
  }

  Widget _buildNavItem(
    WidgetRef ref,
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
    BuildContext context,
  ) {
    final isSelected =
        _getSelectedIndex(GoRouterState.of(context).matchedLocation) == index;
    return InkWell(
      onTap: () => _onItemTapped(index, context),
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSelected ? activeIcon : icon,
            color:
                isSelected
                    ? AppTheme.primaryColor
                    : AppTheme.secondaryTextColor,
            size: 32,
          ),
          const SizedBox(height: 4),
          Text(
            AppTranslations.getText(ref, label),
            style: TextStyle(
              color:
                  isSelected
                      ? AppTheme.primaryColor
                      : AppTheme.secondaryTextColor,
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddRecipeOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (_) => Consumer(
            builder:
                (context, ref, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: _optionIcon(Icons.camera_alt_outlined),
                        title: _optionTitle(ref, 'scan_recipe'),
                        subtitle: _optionSubtitle(
                          ref,
                          'scan_recipe_description',
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/scan-recipe');
                        },
                      ),
                      const Divider(),
                      ListTile(
                        leading: _optionIcon(Icons.link_outlined),
                        title: _optionTitle(ref, 'import_recipe'),
                        subtitle: _optionSubtitle(
                          ref,
                          'import_recipe_description',
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/import-recipe');
                        },
                      ),
                      const Divider(),
                      ListTile(
                        leading: _optionIcon(Icons.add_circle_outline),
                        title: _optionTitle(ref, 'create_recipe'),
                        subtitle: _optionSubtitle(
                          ref,
                          'create_recipe_description',
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/add-recipe');
                        },
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Widget _optionIcon(IconData icon) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: AppTheme.primaryColor.withOpacity(.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, color: AppTheme.primaryColor),
  );

  Text _optionTitle(WidgetRef ref, String key) => Text(
    AppTranslations.getText(ref, key),
    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500),
  );

  Text _optionSubtitle(WidgetRef ref, String key) => Text(
    AppTranslations.getText(ref, key),
    style: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
  );
}

class HomeContent extends ConsumerStatefulWidget {
  const HomeContent({super.key});

  @override
  ConsumerState<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<HomeContent> {
  final TextEditingController _controller = TextEditingController();

  void _handleSearch(String query) {
    if (query.trim().length < 2) return;
    // TODO: Implement search functionality
    print('Searching for: $query');
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(auth.authProvider);
    final userAsync = ref.watch(auth.userDataProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showAsGrid = ref.watch(gridViewProvider);
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Column(
        children: [
          _header(context, topPadding),
          Expanded(
            child: userAsync.when(
              data: (user) => _body(context, user, isDark, showAsGrid),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error loading user: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, double topPadding) => Container(
    decoration: BoxDecoration(
      color: AppTheme.primaryColor,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(20),
        bottomRight: Radius.circular(20),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.1),
          blurRadius: 6,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    padding: EdgeInsets.only(top: topPadding, bottom: 20, left: 16, right: 16),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppTranslations.getText(ref, 'home'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.notifications_outlined,
                color: Colors.white,
              ),
              onPressed: () {},
            ),
          ],
        ),
        const SizedBox(height: 12),
        _searchBar(context),
      ],
    ),
  );

  Widget _searchBar(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(30),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: TextField(
        controller: _controller,
        style: const TextStyle(color: Colors.black87, fontSize: 14),
        textInputAction: TextInputAction.search,
        onSubmitted: (value) => _handleSearch(value),
        decoration: InputDecoration(
          hintText: AppTranslations.getText(ref, 'search_recipes'),
          hintStyle: TextStyle(color: Colors.grey[400]),
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _controller.clear();
                    _handleSearch('');
                    setState(() {}); // update suffix icon visibility
                  },
                ),
              IconButton(
                icon: const Icon(
                  Icons.filter_list,
                  color: AppTheme.primaryColor,
                ),
                onPressed: () => _showFilterDialog(context),
              ),
            ],
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: (value) {
          setState(() {}); // update clear button visibility
          if (value.length > 2) _handleSearch(value);
        },
      ),
    ),
  );

  Widget _body(
    BuildContext context,
    AppUser? user,
    bool isDark,
    bool showAsGrid,
  ) {
    if (user == null) return _emptyState();
    final recipesAsync = ref.watch(userRecipesProvider(user.id));

    return recipesAsync.when(
      data: (recipes) {
        if (recipes.isEmpty) return _emptyState();
        final favsUI = ref.watch(favoritesUIProvider);
        final favorites =
            recipes
                .where(
                  (r) =>
                      favsUI.contains(r.id) ||
                      user.favoriteRecipes.contains(r.id),
                )
                .toList();
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (favorites.isNotEmpty)
                _favoritesSection(context, favorites, isDark, user),
              _allHeader(showAsGrid),
              showAsGrid
                  ? _grid(context, recipes)
                  : _list(context, recipes, isDark, user),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (e, _) => Center(
            child: Text(
              AppTranslations.getText(
                ref,
                'error_loading_recipes',
              ).replaceAll('{error}', e.toString()),
            ),
          ),
    );
  }

  Widget _favoritesSection(
    BuildContext context,
    List<Recipe> favs,
    bool isDark,
    AppUser user,
  ) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppTranslations.getText(ref, 'your_favorites'),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? AppTheme.darkTextColor : AppTheme.textColor,
              ),
            ),
            TextButton(
              onPressed: () => context.go('/favorites'),
              child: Row(
                children: [
                  Text(
                    AppTranslations.getText(ref, 'see_all'),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: AppTheme.primaryColor,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      SizedBox(
        height: 150,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: favs.length,
          itemBuilder: (_, i) => _favCard(context, favs[i], isDark, ref, user),
        ),
      ),
    ],
  );

  Widget _allHeader(bool showAsGrid) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          AppTranslations.getText(ref, 'all_recipes'),
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        IconButton(
          icon: Icon(
            showAsGrid ? Icons.view_list : Icons.grid_view,
            color: AppTheme.primaryColor,
          ),
          onPressed:
              () => ref.read(gridViewProvider.notifier).state = !showAsGrid,
        ),
      ],
    ),
  );

  Widget _grid(BuildContext context, List<Recipe> recipes) => GridView.builder(
    padding: const EdgeInsets.all(16),
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      childAspectRatio: 2.5, // Even less tall cards (wider)
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    ),
    itemCount: recipes.length,
    itemBuilder:
        (_, i) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: RecipeCard(
            recipe: recipes[i],
            onTap: () => context.push('/recipe/${recipes[i].id}'),
            showFavoriteButton: true,
            isCompact: true,
          ),
        ),
  );

  Widget _list(
    BuildContext context,
    List<Recipe> recipes,
    bool isDark,
    AppUser user,
  ) => ListView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: recipes.length,
    itemBuilder: (_, i) => _fullTile(context, recipes[i], isDark, ref, user),
  );

  Widget _emptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(60),
            border: Border.all(
              color: AppTheme.primaryColor.withOpacity(.5),
              width: 2,
            ),
          ),
          child: Icon(
            Icons.restaurant_menu,
            size: 60,
            color: AppTheme.primaryColor.withOpacity(.5),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          AppTranslations.getText(ref, 'no_recipes_yet'),
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textColor,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            AppTranslations.getText(ref, 'add_first_recipe'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              color: AppTheme.secondaryTextColor,
            ),
          ),
        ),
      ],
    ),
  );

  void _toggleFavoriteUI(WidgetRef ref, Recipe recipe) {
    ref.read(favoritesUIProvider.notifier).update((state) {
      final newSet = {...state};
      newSet.contains(recipe.id)
          ? newSet.remove(recipe.id)
          : newSet.add(recipe.id);
      return newSet;
    });
    ref.read(recipeStateProvider.notifier).toggleFavorite(recipe);
  }

  Widget _favCard(
    BuildContext context,
    Recipe recipe,
    bool isDark,
    WidgetRef ref,
    AppUser user,
  ) {
    final favsUI = ref.watch(favoritesUIProvider);
    final isFav =
        favsUI.contains(recipe.id) || user.favoriteRecipes.contains(recipe.id);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.push('/recipe/${recipe.id}'),
        child: Container(
          width: 220,
          height: 130,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isDark ? AppTheme.darkCardColor : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.05),
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Stack(
            children: [
              _imageSection(recipe),
              Positioned(
                top: 5,
                left: 5,
                child: GestureDetector(
                  onTap: () => _toggleFavoriteUI(ref, recipe),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      size: 16,
                      color: isFav ? Colors.red : Colors.white,
                    ),
                  ),
                ),
              ),
              _cardInfo(recipe, isDark, ref),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageSection(Recipe recipe) => ClipRRect(
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(16),
      topRight: Radius.circular(16),
    ),
    child: Container(
      height: 90,
      width: double.infinity,
      decoration: BoxDecoration(
        color:
            recipe.imageUrl.isEmpty
                ? AppTheme.primaryColor.withOpacity(.1)
                : null,
      ),
      child:
          recipe.imageUrl.isNotEmpty
              ? CachedNetworkImage(
                imageUrl: ImageService().getCorsProxiedUrl(recipe.imageUrl),
                fit: BoxFit.cover,
                placeholder:
                    (_, __) => const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryColor,
                      ),
                    ),
                errorWidget:
                    (_, __, ___) => Container(
                      color: AppTheme.primaryColor.withOpacity(.1),
                      child: const Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: AppTheme.primaryColor,
                          size: 28,
                        ),
                      ),
                    ),
              )
              : const Icon(
                Icons.restaurant_menu,
                color: AppTheme.primaryColor,
                size: 40,
              ),
    ),
  );

  Widget _cardInfo(Recipe recipe, bool isDark, WidgetRef ref) => Positioned(
    bottom: 0,
    left: 0,
    right: 0,
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color:
            isDark
                ? AppTheme.darkCardColor.withOpacity(.8)
                : Colors.white.withOpacity(.9),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            recipe.title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.schedule,
                size: 14,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 4),
              Text(
                Helpers.formatCookingTimeWithRef(
                  recipe.prepTime + recipe.cookTime,
                  ref,
                ),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _fullTile(
    BuildContext context,
    Recipe recipe,
    bool isDark,
    WidgetRef ref,
    AppUser user,
  ) {
    final favsUI = ref.watch(favoritesUIProvider);
    final isFav =
        favsUI.contains(recipe.id) || user.favoriteRecipes.contains(recipe.id);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.push('/recipe/${recipe.id}'),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isDark ? AppTheme.darkCardColor : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.05),
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              _listImage(recipe),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              recipe.title,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _toggleFavoriteUI(ref, recipe),
                            child: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              size: 18,
                              color:
                                  isFav
                                      ? Colors.red
                                      : (isDark
                                          ? Colors.white38
                                          : Colors.black38),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (recipe.description.isNotEmpty)
                        Text(
                          recipe.description,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _infoChip(
                            Icons.schedule,
                            Helpers.formatCookingTimeWithRef(
                              recipe.prepTime + recipe.cookTime,
                              ref,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _infoChip(Icons.restaurant, '${recipe.servings}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listImage(Recipe recipe) => ClipRRect(
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(12),
      bottomLeft: Radius.circular(12),
    ),
    child: Container(
      width: 100,
      height: 100,
      color:
          recipe.imageUrl.isEmpty
              ? AppTheme.primaryColor.withOpacity(.1)
              : null,
      child:
          recipe.imageUrl.isNotEmpty
              ? CachedNetworkImage(
                imageUrl: ImageService().getCorsProxiedUrl(recipe.imageUrl),
                fit: BoxFit.cover,
                placeholder:
                    (_, __) => const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryColor,
                      ),
                    ),
                errorWidget:
                    (_, __, ___) => Container(
                      color: AppTheme.primaryColor.withOpacity(.1),
                      child: const Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
              )
              : const Icon(
                Icons.restaurant_menu,
                color: AppTheme.primaryColor,
                size: 36,
              ),
    ),
  );

  Widget _infoChip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppTheme.primaryColor.withOpacity(.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppTheme.primaryColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: AppTheme.primaryColor,
          ),
        ),
      ],
    ),
  );

  void _showFilterDialog(BuildContext context) {
    bool filterFav = false;
    int maxTime = 180;
    double minRating = 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (_) => StatefulBuilder(
            builder:
                (ctx, setState) => Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 80,
                    top: 16,
                    left: 16,
                    right: 16,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              AppTranslations.getText(ref, 'filter'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        const Divider(),
                        SwitchListTile(
                          title: Text(
                            AppTranslations.getText(ref, 'favorites_only'),
                          ),
                          value: filterFav,
                          activeColor: AppTheme.primaryColor,
                          onChanged: (v) => setState(() => filterFav = v),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          title: Text(
                            AppTranslations.getText(ref, 'max_cooking_time'),
                          ),
                          subtitle: Text(
                            Helpers.formatCookingTimeWithRef(maxTime, ref),
                          ),
                        ),
                        Slider(
                          value: maxTime.toDouble(),
                          min: 10,
                          max: 180,
                          divisions: 17,
                          activeColor: AppTheme.primaryColor,
                          inactiveColor: AppTheme.primaryColor.withOpacity(.2),
                          label: Helpers.formatCookingTimeWithRef(maxTime, ref),
                          onChanged: (v) => setState(() => maxTime = v.toInt()),
                        ),
                        const SizedBox(height: 16),
                        ListTile(
                          title: Text(
                            AppTranslations.getText(ref, 'min_rating'),
                          ),
                          subtitle: Text(
                            minRating == 0
                                ? AppTranslations.getText(ref, 'any_rating')
                                : '${minRating.toStringAsFixed(1)} ${AppTranslations.getText(ref, 'stars')} ${AppTranslations.getText(ref, 'rating_and_up')}',
                          ),
                        ),
                        Slider(
                          value: minRating,
                          min: 0,
                          max: 5,
                          divisions: 10,
                          activeColor: AppTheme.primaryColor,
                          inactiveColor: AppTheme.primaryColor.withOpacity(.2),
                          label:
                              minRating == 0
                                  ? AppTranslations.getText(ref, 'any')
                                  : '${minRating.toStringAsFixed(1)}+',
                          onChanged: (v) => setState(() => minRating = v),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    AppTranslations.getText(
                                      ref,
                                      'filters_applied',
                                    ),
                                  ),
                                  backgroundColor: AppTheme.primaryColor,
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                            child: Text(
                              AppTranslations.getText(ref, 'apply_filters'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }
}
