import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String name;
  final String email;
  final String photoUrl;
  final List<String> favoriteRecipes;
  final DateTime createdAt;
  final DateTime lastLogin;
  final List<String> recipes;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.photoUrl = '',
    this.favoriteRecipes = const [],
    this.recipes = const [],
    DateTime? createdAt,
    DateTime? lastLogin,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastLogin = lastLogin ?? DateTime.now();

  // Getters for recipe and favorite counts
  int get recipeCount => recipes.length;
  int get favoriteCount => favoriteRecipes.length;

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? photoUrl,
    List<String>? favoriteRecipes,
    List<String>? recipes,
    DateTime? createdAt,
    DateTime? lastLogin,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      favoriteRecipes: favoriteRecipes ?? this.favoriteRecipes,
      recipes: recipes ?? this.recipes,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'photoUrl': photoUrl,
      'favoriteRecipes': favoriteRecipes,
      'recipes': recipes,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLogin': Timestamp.fromDate(lastLogin),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
      photoUrl: map['photoUrl'] as String? ?? '',
      favoriteRecipes: List<String>.from(map['favoriteRecipes'] ?? []),
      recipes: List<String>.from(map['recipes'] ?? []),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      lastLogin: (map['lastLogin'] as Timestamp).toDate(),
    );
  }

  @override
  String toString() {
    return 'UserModel(id: $id, name: $name, email: $email)';
  }
} 