import 'package:cloud_firestore/cloud_firestore.dart';

class Category {
  final String id;
  final String name;
  final String icon;
  final String? userId;

  Category({
    required this.id,
    required this.name,
    required this.icon,
    this.userId,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'icon': icon, 'userId': userId};
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as String,
      name: map['name'] as String,
      icon: map['icon'] as String,
      userId: map['userId'] as String?,
    );
  }

  factory Category.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Category(
      id: doc.id,
      name: data['name'] ?? '',
      icon: data['icon'] ?? '',
      userId: data['userId'],
    );
  }
}
