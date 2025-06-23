import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/providers/recipe_provider.dart';
import 'package:recipe_keeper/widgets/recipe_form.dart';
import 'package:recipe_keeper/utils/translations.dart';

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
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 900;

    return recipeAsync.when(
      data: (recipe) {
        if (recipe == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(AppTranslations.getText(ref, 'edit_recipe')),
            ),
            body: Center(
              child: Text(AppTranslations.getText(ref, 'recipe_not_found')),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(AppTranslations.getText(ref, 'edit_recipe')),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.save),
                tooltip: AppTranslations.getText(ref, 'save_changes'),
                onPressed: () {
                  // Show saving indicator
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppTranslations.getText(ref, 'saving')),
                      backgroundColor: Colors.green,
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
            ],
            elevation: 0, // Remove shadow for a more modern look
            backgroundColor:
                Theme.of(context).brightness == Brightness.dark
                    ? Colors.black54
                    : Theme.of(context).primaryColor,
          ),
          body: Container(
            color:
                Theme.of(context).brightness == Brightness.dark
                    ? Colors.black12
                    : Colors.grey[50],
            child: Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isLargeScreen ? 900 : double.infinity,
                ),
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
                        SnackBar(
                          content: Text(
                            AppTranslations.getText(
                              ref,
                              'recipe_updated_successfully',
                            ),
                          ),
                          backgroundColor: Colors.green,
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
        );
      },
      loading:
          () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
      error:
          (error, stackTrace) => Scaffold(
            appBar: AppBar(
              title: Text(AppTranslations.getText(ref, 'edit_recipe')),
            ),
            body: Center(child: Text('Error: ${error.toString()}')),
          ),
    );
  }
}
