import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/services/shopping_list_service.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/providers/settings_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:recipe_keeper/utils/translations.dart';

class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({super.key});

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  final TextEditingController _itemController = TextEditingController();
  final ShoppingListService _shoppingListService = ShoppingListService();

  @override
  void dispose() {
    _itemController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final userId = authState.user?.uid;

    if (userId == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: const Center(
          child: Text('Please log in to view your shopping list'),
        ),
        bottomNavigationBar: const AppBottomNav(currentIndex: 1),
      );
    }

    return Scaffold(
      extendBody: true,
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          AppHeader(title: AppTranslations.getText(ref, 'shopping_list_title')),
          // Action buttons row
          StreamBuilder<List<ShoppingItem>>(
            stream: _shoppingListService.getShoppingList(userId),
            builder: (context, snapshot) {
              final hasItems = snapshot.hasData && snapshot.data!.isNotEmpty;
              if (!hasItems) return const SizedBox.shrink();

              final isHebrew =
                  ref.watch(settingsProvider).language == AppLanguage.hebrew;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                height: 48, // Add specific height for Stack
                child:
                    isHebrew
                        ? Stack(
                          children: [
                            // Share button (left for Hebrew)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.share,
                                  color: AppTheme.secondaryTextColor,
                                ),
                                onPressed:
                                    () => _shareShoppingList(snapshot.data!),
                                tooltip: AppTranslations.getText(
                                  ref,
                                  'share_list',
                                ),
                              ),
                            ),
                            // Clear checked items button (right for Hebrew)
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              child: TextButton.icon(
                                onPressed: () => _clearCheckedItems(userId),
                                icon: const Icon(Icons.clear_all, size: 20),
                                label: Text(
                                  AppTranslations.getText(
                                    ref,
                                    'clear_checked_items',
                                  ),
                                  style: TextStyle(
                                    fontFamily: AppTheme.primaryFontFamily,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.secondaryTextColor,
                                ),
                              ),
                            ),
                          ],
                        )
                        : Stack(
                          children: [
                            // Clear checked items button (left for English)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              child: TextButton.icon(
                                onPressed: () => _clearCheckedItems(userId),
                                icon: const Icon(Icons.clear_all, size: 20),
                                label: Text(
                                  AppTranslations.getText(
                                    ref,
                                    'clear_checked_items',
                                  ),
                                  style: TextStyle(
                                    fontFamily: AppTheme.primaryFontFamily,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.secondaryTextColor,
                                ),
                              ),
                            ),
                            // Share button (right for English)
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.share,
                                  color: AppTheme.secondaryTextColor,
                                ),
                                onPressed:
                                    () => _shareShoppingList(snapshot.data!),
                                tooltip: AppTranslations.getText(
                                  ref,
                                  'share_list',
                                ),
                              ),
                            ),
                          ],
                        ),
              );
            },
          ),
          // Add item section
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _itemController,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      hintText: AppTranslations.getText(
                        ref,
                        'add_item_to_list',
                      ),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted:
                        (value) => _addItem(userId, showMessage: false),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: () => _addItem(userId, showMessage: false),
                  backgroundColor: AppTheme.primaryColor,
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          // Shopping list
          Expanded(
            child: StreamBuilder<List<ShoppingItem>>(
              stream: _shoppingListService.getShoppingList(userId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                    ),
                  );
                }

                final items = snapshot.data ?? [];

                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 64,
                          color: AppTheme.secondaryTextColor,
                        ),
                        SizedBox(height: 16),
                        Text(
                          AppTranslations.getText(ref, 'list_is_empty'),
                          style: TextStyle(
                            fontSize: 18,
                            color: AppTheme.secondaryTextColor,
                            fontFamily: AppTheme.primaryFontFamily,
                          ),
                        ),
                        Text(
                          AppTranslations.getText(
                            ref,
                            'add_items_to_shopping_list',
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.secondaryTextColor,
                            fontFamily: AppTheme.primaryFontFamily,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];

                    return ListTile(
                      leading: Checkbox(
                        value: item.isChecked,
                        onChanged: (value) {
                          _updateItem(userId, item.id, value ?? false);
                        },
                        activeColor: AppTheme.primaryColor,
                      ),
                      title: Text(
                        item.name,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontFamily: AppTheme.primaryFontFamily,
                          decoration:
                              item.isChecked
                                  ? TextDecoration.lineThrough
                                  : null,
                          color:
                              item.isChecked
                                  ? AppTheme.secondaryTextColor
                                  : AppTheme.textColor,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _removeItem(userId, item.id),
                        color: AppTheme.errorColor,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }

  Future<void> _addItem(String userId, {bool showMessage = true}) async {
    final item = _itemController.text.trim();
    if (item.isEmpty) return;

    try {
      await _shoppingListService.addItem(userId, item);
      _itemController.clear();

      if (showMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'item_added_to_list'),
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
            ),
            backgroundColor: AppTheme.primaryColor,
            duration: const Duration(seconds: 2),
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
        } else if (e.toString().contains('already exists')) {
          errorMessage = AppTranslations.getText(ref, 'item_already_in_list');
          backgroundColor = AppTheme.primaryColor.withOpacity(0.8);
        } else {
          errorMessage = AppTranslations.getText(
            ref,
            'error_adding_item_generic',
          );
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

  Future<void> _updateItem(String userId, String itemId, bool isChecked) async {
    try {
      await _shoppingListService.updateItem(userId, itemId, isChecked);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'error_updating_item'),
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
            ),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _removeItem(String userId, String itemId) async {
    try {
      await _shoppingListService.deleteItem(userId, itemId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'error_deleting_item'),
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
            ),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _clearCheckedItems(String userId) async {
    try {
      await _shoppingListService.clearCheckedItems(userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'checked_items_deleted'),
              textAlign: TextAlign.right,
              style: TextStyle(fontFamily: AppTheme.primaryFontFamily),
            ),
            backgroundColor: AppTheme.primaryColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'error_deleting_items'),
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
            ),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  void _shareShoppingList(List<ShoppingItem> items) {
    final StringBuffer shareText = StringBuffer();
    shareText.writeln(
      '🛒 ${AppTranslations.getText(ref, 'shopping_list_share_title')}',
    );
    shareText.writeln();

    final uncheckedItems = items.where((item) => !item.isChecked).toList();
    final checkedItems = items.where((item) => item.isChecked).toList();

    if (uncheckedItems.isNotEmpty) {
      shareText.writeln('${AppTranslations.getText(ref, 'items_to_buy')}:');
      for (int i = 0; i < uncheckedItems.length; i++) {
        shareText.writeln('☐ ${uncheckedItems[i].name}');
      }
      shareText.writeln();
    }

    if (checkedItems.isNotEmpty) {
      shareText.writeln('${AppTranslations.getText(ref, 'items_bought')}:');
      for (int i = 0; i < checkedItems.length; i++) {
        shareText.writeln('☑ ${checkedItems[i].name}');
      }
      shareText.writeln();
    }

    shareText.writeln(
      AppTranslations.getText(ref, 'shared_from_recipe_keeper'),
    );

    Share.share(shareText.toString());
  }
}
