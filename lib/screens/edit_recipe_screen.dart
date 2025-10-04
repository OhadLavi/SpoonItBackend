import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/providers/recipe_provider.dart';
import 'package:recipe_keeper/widgets/recipe_form.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';
import 'package:recipe_keeper/utils/app_theme.dart';

class EditRecipeScreen extends ConsumerStatefulWidget {
  final String recipeId;

  const EditRecipeScreen({super.key, required this.recipeId});

  @override
  ConsumerState<EditRecipeScreen> createState() => _EditRecipeScreenState();
}

class _EditRecipeScreenState extends ConsumerState<EditRecipeScreen> {
  GlobalKey<FormState>? _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final recipeAsync = ref.watch(recipeProvider(widget.recipeId));

    return recipeAsync.when(
      data: (recipe) {
        if (recipe == null) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Column(
              children: [
                AppHeader(
                  title: 'עריכת מתכון',
                  showBackButton: true,
                  onBackPressed: () => context.pop(),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.restaurant_menu,
                          size: 80,
                          color: AppTheme.secondaryTextColor.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'המתכון לא נמצא',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const AppBottomNav(currentIndex: -1),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          body: Column(
            children: [
              AppHeader(
                title: 'עריכת מתכון',
                showBackButton: true,
                onBackPressed: () => context.pop(),
                customContent: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Text(
                            recipe.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Heebo',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.save,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () {
                          // Show saving indicator
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'שומר...',
                                style: TextStyle(
                                  fontFamily: 'Heebo',
                                  color: Colors.white,
                                ),
                              ),
                              backgroundColor: const Color(0xFFFF7E6B),
                              duration: const Duration(seconds: 1),
                            ),
                          );

                          // Use the form key to trigger validation and submission
                          final formState = _formKey?.currentState;
                          if (formState != null && formState.validate()) {
                            // This will call the onSubmit callback on the RecipeForm
                            // which already handles the success messaging and navigation
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  color: const Color(0xFFF8F8F8),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Card(
                        margin: const EdgeInsets.all(16.0),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: RecipeForm(
                          initialRecipe: recipe,
                          isEditing: true,
                          onFormReady: (key) {
                            // Store the key reference directly without setState
                            _formKey = key;
                          },
                          onSubmit: () {
                            // Handle successful save callback - this will be called after form validation
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'המתכון עודכן בהצלחה!',
                                  style: TextStyle(
                                    fontFamily: 'Heebo',
                                    color: Colors.white,
                                  ),
                                ),
                                backgroundColor: Color(0xFFFF7E6B),
                              ),
                            );
                            // Navigate to recipe detail screen after successful save
                            context.go('/recipe/${recipe.id}');
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const AppBottomNav(currentIndex: -1),
            ],
          ),
        );
      },
      loading:
          () => Scaffold(
            backgroundColor: Colors.white,
            body: Column(
              children: [
                AppHeader(
                  title: 'עריכת מתכון',
                  showBackButton: true,
                  onBackPressed: () => context.pop(),
                ),
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF7E6B)),
                  ),
                ),
                const AppBottomNav(currentIndex: -1),
              ],
            ),
          ),
      error:
          (error, stackTrace) => Scaffold(
            backgroundColor: Colors.white,
            body: Column(
              children: [
                AppHeader(
                  title: 'עריכת מתכון',
                  showBackButton: true,
                  onBackPressed: () => context.pop(),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 80,
                          color: AppTheme.secondaryTextColor.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'שגיאה בטעינת המתכון',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error.toString(),
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: AppTheme.secondaryTextColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const AppBottomNav(currentIndex: -1),
              ],
            ),
          ),
    );
  }
}
