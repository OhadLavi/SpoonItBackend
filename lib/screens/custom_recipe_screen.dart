import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';
import 'package:recipe_keeper/config/env_config.dart';

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
          const AppHeader(title: 'מתכון מותאם'),
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
                  TextField(
                    controller: _groceriesController,
                    decoration: InputDecoration(
                      hintText: AppTranslations.getText(ref, 'groceries_hint'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppTranslations.getText(ref, 'what_do_you_want'),
                    style: AppTheme.headingStyle,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      hintText: AppTranslations.getText(
                        ref,
                        'recipe_description_hint',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _generateRecipe,
                      child:
                          _loading
                              ? const CircularProgressIndicator(
                                color: AppTheme.primaryColor,
                              )
                              : Text(
                                AppTranslations.getText(ref, 'generate_recipe'),
                              ),
                    ),
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
