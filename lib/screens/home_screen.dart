import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/services/category_service.dart';
import 'package:recipe_keeper/models/category.dart';
import 'package:recipe_keeper/widgets/settings_menu.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';
import 'package:recipe_keeper/widgets/add_category_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';

final gridViewProvider = StateProvider<bool>((ref) => false);
final favoritesUIProvider = StateProvider<Set<String>>((ref) => <String>{});
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

  // Default categories for new users
  final List<Map<String, dynamic>> _defaultCategories = [
    {'label': 'מאפים', 'icon': Icons.cake, 'iconName': 'cake'},
    {'label': 'עיקריות', 'icon': Icons.room_service, 'iconName': 'room_service'},
    {'label': 'תוספות', 'icon': Icons.fastfood, 'iconName': 'fastfood'},
    {'label': 'עוגיות', 'icon': Icons.cookie, 'iconName': 'cookie'},
    {'label': 'עוגות', 'icon': Icons.cake_outlined, 'iconName': 'cake_outlined'},
    {'label': 'סלטים', 'icon': Icons.ramen_dining, 'iconName': 'ramen_dining'},
    {'label': 'לחמים', 'icon': Icons.bakery_dining, 'iconName': 'bakery_dining'},
  ];

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return Scaffold(
      backgroundColor: Colors.white,
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
                  behavior: ScrollConfiguration.of(context).copyWith(
                    scrollbars: false,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'קטגוריות',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 28,
                              fontFamily: 'Poppins',
                              color: Color(0xFF6E3C3F),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 16),
                        user != null 
                          ? _buildDynamicCategoriesGrid(context, user.uid)
                          : _buildDefaultCategoriesGrid(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const AppBottomNav(currentIndex: 0),
        ],
      ),
    );
  }


  void _showSettings(BuildContext context) {
    final hostContext = context; // <-- stable parent context
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, __, ___) {
        final w = MediaQuery.of(context).size.width;
        final h = MediaQuery.of(context).size.height;
        final panelW = w < 520 ? 320.0 : 380.0;

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Panel
                Container(
                  width: panelW,
                  height: h,
                  decoration: const BoxDecoration(
                    color: Color(0xFF3A3638),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: SettingsMenu(
                        hostContext: hostContext,
                      ), // <-- pass it in
                    ),
                  ),
                ),

                // Peach ear with RIGHT chevron (like the mock)
                Positioned(
                  left: -18,
                  top: 12,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF7E6B),
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(12),
                          right: Radius.circular(12),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.chevron_right, // → matches the mock
                        size: 20,
                        color: Colors.white,
                        textDirection: TextDirection.ltr, // prevent RTL flip
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
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          textAlign: TextAlign.right,
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(fontSize: 16, color: Color(0xFF8D5B5B)),
          cursorColor: const Color(0xFF8D5B5B),
          decoration: const InputDecoration(
            isCollapsed: true,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hintText: 'חיפוש',
            hintStyle: TextStyle(color: Color(0xFF8D5B5B), fontSize: 16),
            // In RTL, prefixIcon appears on the right
            prefixIcon: Padding(
              padding: EdgeInsets.only(left: 8, right: 8),
              child: Icon(Icons.search, size: 20, color: Color(0xFF8D5B5B)),
            ),
            prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              context.push('/search');
            }
          },
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
      loading: () => Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF7E6B)),
        ),
      ),
      error: (error, stack) => Center(
        child: Text(
          'שגיאה בטעינת הקטגוריות',
          style: TextStyle(
            color: Color(0xFF6E3C3F),
            fontFamily: 'Poppins',
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultCategoriesGrid(BuildContext context) {
    return _buildCategoriesList(context, _defaultCategories, false);
  }

  Widget _buildCategoriesList(BuildContext context, List<dynamic> categories, bool isDynamic) {
    // Calculate responsive sizes based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize = (screenWidth * 0.08).clamp(32.0, 60.0);
    final fontSize = (screenWidth * 0.035).clamp(12.0, 18.0);
    final spacing = (screenWidth * 0.08).clamp(16.0, 32.0);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.9,
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
                      Icon(Icons.add, size: iconSize, color: Colors.grey),
                      SizedBox(height: iconSize * 0.2),
                      Text(
                        'הוסף קטגוריה',
                        style: TextStyle(
                          fontSize: fontSize,
                          color: Colors.grey,
                          fontFamily: 'Poppins',
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
              final String label = isDynamic 
                ? category.name 
                : category['label'] as String;
              setState(() {
                selectedCategoryIndex = index;
              });
              context.push('/category/$label');
            },
            child: Container(
              decoration: BoxDecoration(
                color: Color(0xFFF8F8F8),
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                  ? Border.all(color: Color(0xFFFF7E6B), width: 2)
                  : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _getIconFromName(isDynamic ? category.icon : category['iconName']),
                      size: iconSize,
                      color: Color(0xFFFF7E6B),
                    ),
                    SizedBox(height: iconSize * 0.3),
                    Text(
                      isDynamic ? category.name : category['label'] as String,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6E3C3F),
                        fontFamily: 'Poppins',
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

  IconData _getIconFromName(String iconName) {
    switch (iconName) {
      case 'cake': return Icons.cake;
      case 'room_service': return Icons.room_service;
      case 'fastfood': return Icons.fastfood;
      case 'cookie': return Icons.cookie;
      case 'cake_outlined': return Icons.cake_outlined;
      case 'ramen_dining': return Icons.ramen_dining;
      case 'bakery_dining': return Icons.bakery_dining;
      case 'local_pizza': return Icons.local_pizza;
      case 'restaurant': return Icons.restaurant;
      case 'coffee': return Icons.coffee;
      case 'ice_cream': return Icons.ac_unit;
      case 'lunch_dining': return Icons.lunch_dining;
      default: return Icons.category;
    }
  }

  void _showAddCategoryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const AddCategoryDialog(),
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
          color: Colors.white,
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
          ..color = Colors.grey
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
