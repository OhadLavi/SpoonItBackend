import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/utils/translations.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:spoonit/widgets/app_header.dart';
import 'package:spoonit/widgets/app_bottom_nav.dart';
import 'package:spoonit/config/env_config.dart';
import 'package:spoonit/widgets/forms/app_text_field.dart';
import 'package:spoonit/widgets/forms/app_form_container.dart';
import 'package:spoonit/widgets/buttons/app_primary_button.dart';

class CustomRecipeScreen extends ConsumerStatefulWidget {
  const CustomRecipeScreen({super.key});

  @override
  ConsumerState<CustomRecipeScreen> createState() => _CustomRecipeScreenState();
}

class _CustomRecipeScreenState extends ConsumerState<CustomRecipeScreen> {
  final TextEditingController _groceriesController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _generatedRecipe = '';
  bool _loading = false;

  Future<void> _generateRecipe() async {
    setState(() {
      _loading = true;
    });
    final url = '${EnvConfig.apiBaseUrl}/custom_recipe';
    final body = json.encode({
      'groceries': _groceriesController.text,
      'description': _descriptionController.text,
    });
    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          _generatedRecipe = json.encode(
            data,
            toEncodable: (o) => o.toString(),
          );
        });
      } else {
        setState(() {
          _generatedRecipe = 'Error: ${res.body}';
        });
      }
    } catch (e) {
      setState(() {
        _generatedRecipe = 'Error: $e';
      });
    }
    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          AppHeader(title: AppTranslations.getText(ref, 'custom_recipe')),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppTranslations.getText(ref, 'enter_your_groceries'),
                    style: AppTheme.headingStyle,
                  ),
                  const SizedBox(height: 8),
                  AppFormContainer(
                    child: AppTextField(
                      controller: _groceriesController,
                      hintText: AppTranslations.getText(ref, 'groceries_hint'),
                      maxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppTranslations.getText(ref, 'what_do_you_want'),
                    style: AppTheme.headingStyle,
                  ),
                  const SizedBox(height: 8),
                  AppFormContainer(
                    child: AppTextField(
                      controller: _descriptionController,
                      hintText: AppTranslations.getText(
                        ref,
                        'recipe_description_hint',
                      ),
                      maxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppPrimaryButton(
                    text: AppTranslations.getText(ref, 'generate_recipe'),
                    onPressed: _loading ? null : _generateRecipe,
                    isLoading: _loading,
                    width: double.infinity,
                  ),
                  const SizedBox(height: 24),
                  if (_generatedRecipe.isNotEmpty)
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          _generatedRecipe,
                          style: const TextStyle(
                            fontFamily: AppTheme.secondaryFontFamily,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: -1),
    );
  }
}
