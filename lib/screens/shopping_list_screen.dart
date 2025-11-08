import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoonit/widgets/app_header.dart';
import 'package:spoonit/widgets/app_bottom_nav.dart';
import 'package:spoonit/utils/app_theme.dart';
import 'package:spoonit/services/shopping_list_service.dart';
import 'package:spoonit/providers/auth_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:spoonit/utils/translations.dart';

class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({super.key});

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  final TextEditingController _itemController = TextEditingController();
  final ShoppingListService _shoppingListService = ShoppingListService();
  final FocusNode _itemFocusNode = FocusNode();

  @override
  void dispose() {
    _itemController.dispose();
    _itemFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final userId = authState.user?.uid;

    if (userId == null) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: Center(child: Text('Please log in to view your shopping list')),
        bottomNavigationBar: AppBottomNav(currentIndex: 1),
      );
    }

    if (kDebugMode) {
      developer.log('Building shopping list screen', name: 'ShoppingListScreen');
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          // Header
          AppHeader(
            title: AppTranslations.getText(ref, 'shopping_list_title'),
          ),
          // Add item input section
          _buildAddItemSection(userId),
          // Shopping list items
          Expanded(
            child: _buildShoppingList(userId),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }

  Widget _buildAddItemSection(String userId) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppTheme.backgroundColor,
      child: Row(
        children: [
          // Input field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.dividerColor,
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _itemController,
                focusNode: _itemFocusNode,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: AppTranslations.getText(ref, 'add_item_to_list'),
                  hintStyle: TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    color: AppTheme.secondaryTextColor,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (value) {
                  if (kDebugMode) {
                    developer.log('Item submitted: $value', name: 'ShoppingListScreen');
                  }
                  _addItem(userId);
                },
                onTap: () {
                  if (kDebugMode) {
                    developer.log('Input field tapped', name: 'ShoppingListScreen');
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          
          // Add button
          Material(
            color: AppTheme.primaryColor,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () {
                if (kDebugMode) {
                  developer.log('Add button tapped', name: 'ShoppingListScreen');
                }
                _addItem(userId);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.add,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShoppingList(String userId) {
    return StreamBuilder<List<ShoppingItem>>(
      stream: _shoppingListService.getShoppingList(userId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (kDebugMode) {
            developer.log(
              'Error loading shopping list',
              name: 'ShoppingListScreen',
              error: snapshot.error,
            );
          }
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: AppTheme.errorColor),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: const CircularProgressIndicator(
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
                const Icon(
                  Icons.shopping_cart_outlined,
                  size: 80,
                  color: AppTheme.secondaryTextColor,
                ),
                const SizedBox(height: 16),
                Text(
                  AppTranslations.getText(ref, 'list_is_empty'),
                  style: const TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    fontSize: 18,
                    color: AppTheme.textColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppTranslations.getText(ref, 'add_items_to_shopping_list'),
                  style: TextStyle(
                    fontFamily: AppTheme.secondaryFontFamily,
                    fontSize: 14,
                    color: AppTheme.secondaryTextColor,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Action buttons
            if (items.isNotEmpty) _buildActionButtons(userId),
            
            // List items
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: 80,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _buildShoppingItem(userId, item);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionButtons(String userId) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Clear checked items button
          TextButton.icon(
            onPressed: () {
              if (kDebugMode) {
                developer.log('Clear checked items tapped', name: 'ShoppingListScreen');
              }
              _clearCheckedItems(userId);
            },
            icon: const Icon(Icons.clear_all, size: 18),
            label: Text(
              AppTranslations.getText(ref, 'clear_checked_items'),
              style: const TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: 14,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.secondaryTextColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          
          // Share button
          IconButton(
            onPressed: () {
              if (kDebugMode) {
                developer.log('Share button tapped', name: 'ShoppingListScreen');
              }
              _shareShoppingList();
            },
            icon: const Icon(Icons.share),
            color: AppTheme.secondaryTextColor,
            tooltip: AppTranslations.getText(ref, 'share_list'),
          ),
        ],
      ),
    );
  }

  Widget _buildShoppingItem(String userId, ShoppingItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.dividerColor,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        leading: Checkbox(
          value: item.isChecked,
          onChanged: (value) {
            if (kDebugMode) {
              developer.log(
                'Checkbox toggled: ${item.name} = $value',
                name: 'ShoppingListScreen',
              );
            }
            _updateItem(userId, item.id, value ?? false);
          },
          activeColor: AppTheme.primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        title: Text(
          item.name,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            fontSize: 16,
            decoration: item.isChecked ? TextDecoration.lineThrough : null,
            color: item.isChecked
                ? AppTheme.secondaryTextColor
                : AppTheme.textColor,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          color: AppTheme.errorColor,
          onPressed: () {
            if (kDebugMode) {
              developer.log('Delete item: ${item.name}', name: 'ShoppingListScreen');
            }
            _removeItem(userId, item.id);
          },
          tooltip: AppTranslations.getText(ref, 'delete'),
        ),
      ),
    );
  }

  // Actions
  Future<void> _addItem(String userId) async {
    final item = _itemController.text.trim();
    
    if (kDebugMode) {
      developer.log('_addItem called: "$item"', name: 'ShoppingListScreen');
    }

    if (item.isEmpty) {
      if (kDebugMode) {
        developer.log('Item is empty, not adding', name: 'ShoppingListScreen');
      }
      return;
    }

    try {
      await _shoppingListService.addItem(userId, item);
      _itemController.clear();
      _itemFocusNode.unfocus();
      
      if (kDebugMode) {
        developer.log('Item added successfully', name: 'ShoppingListScreen');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'item_added_to_list'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
            ),
            backgroundColor: AppTheme.primaryColor,
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        developer.log(
          'Error adding item',
          name: 'ShoppingListScreen',
          error: e,
          stackTrace: stackTrace,
        );
      }

      if (mounted) {
        String errorMessage = AppTranslations.getText(ref, 'error_adding_item_generic');
        
        if (e.toString().contains('Shopping list limit reached')) {
          errorMessage = AppTranslations.getText(ref, 'shopping_list_full');
        } else if (e.toString().contains('already exists')) {
          errorMessage = AppTranslations.getText(ref, 'item_already_in_list');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
            ),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _updateItem(String userId, String itemId, bool isChecked) async {
    try {
      await _shoppingListService.updateItem(userId, itemId, isChecked);
      
      if (kDebugMode) {
        developer.log('Item updated: $itemId = $isChecked', name: 'ShoppingListScreen');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        developer.log(
          'Error updating item',
          name: 'ShoppingListScreen',
          error: e,
          stackTrace: stackTrace,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'error_updating_item'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
            ),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _removeItem(String userId, String itemId) async {
    try {
      await _shoppingListService.deleteItem(userId, itemId);
      
      if (kDebugMode) {
        developer.log('Item deleted: $itemId', name: 'ShoppingListScreen');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        developer.log(
          'Error deleting item',
          name: 'ShoppingListScreen',
          error: e,
          stackTrace: stackTrace,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'error_deleting_item'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
            ),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _clearCheckedItems(String userId) async {
    try {
      await _shoppingListService.clearCheckedItems(userId);
      
      if (kDebugMode) {
        developer.log('Checked items cleared', name: 'ShoppingListScreen');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'checked_items_deleted'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
            ),
            backgroundColor: AppTheme.primaryColor,
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        developer.log(
          'Error clearing checked items',
          name: 'ShoppingListScreen',
          error: e,
          stackTrace: stackTrace,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'error_deleting_items'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
            ),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _shareShoppingList() async {
    try {
      final authState = ref.read(authProvider);
      final userId = authState.user?.uid;
      if (userId == null) return;

      final stream = _shoppingListService.getShoppingList(userId);
      final items = await stream.first;

      if (items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppTranslations.getText(ref, 'list_is_empty'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
              ),
              backgroundColor: AppTheme.warningColor,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final StringBuffer shareText = StringBuffer();
      shareText.writeln(
        '🛒 ${AppTranslations.getText(ref, 'shopping_list_share_title')}',
      );
      shareText.writeln();

      final uncheckedItems = items.where((item) => !item.isChecked).toList();
      final checkedItems = items.where((item) => item.isChecked).toList();

      if (uncheckedItems.isNotEmpty) {
        shareText.writeln('${AppTranslations.getText(ref, 'items_to_buy')}:');
        for (final item in uncheckedItems) {
          shareText.writeln('☐ ${item.name}');
        }
        shareText.writeln();
      }

      if (checkedItems.isNotEmpty) {
        shareText.writeln('${AppTranslations.getText(ref, 'items_bought')}:');
        for (final item in checkedItems) {
          shareText.writeln('☑ ${item.name}');
        }
        shareText.writeln();
      }

      shareText.writeln(
        AppTranslations.getText(ref, 'shared_from_recipe_keeper'),
      );

      await SharePlus.instance.share(
        ShareParams(
          text: shareText.toString(),
          subject: AppTranslations.getText(ref, 'shopping_list_share_title'),
        ),
      );
      
      if (kDebugMode) {
        developer.log('Shopping list shared', name: 'ShoppingListScreen');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        developer.log(
          'Error sharing shopping list',
          name: 'ShoppingListScreen',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
  }
}
