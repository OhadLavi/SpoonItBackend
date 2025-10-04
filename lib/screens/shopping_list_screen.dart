import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';

class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({super.key});

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  final List<String> _shoppingItems = [];
  final TextEditingController _itemController = TextEditingController();

  @override
  void dispose() {
    _itemController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const AppHeader(title: 'רשימת הקניות'),
          // Add item section
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _itemController,
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(
                      hintText: 'הוסף פריט לרשימה',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (value) => _addItem(),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _addItem,
                  backgroundColor: const Color(0xFFFF7E6B),
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          // Shopping list
          Expanded(
            child:
                _shoppingItems.isEmpty
                    ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'הרשימה ריקה',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          Text(
                            'הוסף פריטים לרשימת הקניות',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      itemCount: _shoppingItems.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          leading: Checkbox(
                            value: false,
                            onChanged: (value) {
                              // TODO: Implement checkbox functionality
                            },
                          ),
                          title: Text(
                            _shoppingItems[index],
                            textDirection: TextDirection.rtl,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _removeItem(index),
                          ),
                        );
                      },
                    ),
          ),
          const AppBottomNav(currentIndex: 1),
        ],
      ),
    );
  }

  void _addItem() {
    final item = _itemController.text.trim();
    if (item.isNotEmpty) {
      setState(() {
        _shoppingItems.add(item);
        _itemController.clear();
      });
    }
  }

  void _removeItem(int index) {
    setState(() {
      _shoppingItems.removeAt(index);
    });
  }
}
