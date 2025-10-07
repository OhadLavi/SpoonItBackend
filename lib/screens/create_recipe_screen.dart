import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';
import 'package:recipe_keeper/widgets/recipe_form_base.dart';

class CreateRecipeScreen extends ConsumerWidget {
  const CreateRecipeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: RecipeFormBase(
          title: 'יצירת מתכון',
          onSuccess: () => context.go('/home'),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: -1),
    );
  }
}
