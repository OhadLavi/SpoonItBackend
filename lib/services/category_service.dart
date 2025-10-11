import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spoonit/models/category.dart';

class CategoryService {
  final _db = FirebaseFirestore.instance;

  Stream<List<Category>> getCategories(String? userId) {
    return _db
        .collection('categories')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Category.fromFirestore(doc)).toList(),
        );
  }

  Future<void> addCategory(Category category) async {
    await _db.collection('categories').doc(category.id).set(category.toMap());
  }

  Future<void> updateCategory(Category category) async {
    await _db
        .collection('categories')
        .doc(category.id)
        .update(category.toMap());
  }

  Future<void> deleteCategory(String categoryId) async {
    await _db.collection('categories').doc(categoryId).delete();
  }
}
