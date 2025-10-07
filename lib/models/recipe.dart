import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class Recipe {
  final String id;
  final String title;
  final String description;
  final List<String> ingredients;
  final List<String> instructions;
  final String imageUrl;
  final String sourceUrl;
  final String userId;
  final DateTime createdAt;
  final List<String> tags;
  final int prepTime; // in minutes
  final int cookTime; // in minutes
  final int servings;
  final bool isFavorite;
  final String notes;
  final String source;
  final DateTime updatedAt;
  final String? categoryId;

  Recipe({
    String? id,
    required this.title,
    required this.description,
    required this.ingredients,
    required this.instructions,
    this.imageUrl = '',
    this.sourceUrl = '',
    required this.userId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.tags = const [],
    this.prepTime = 0,
    this.cookTime = 0,
    this.servings = 1,
    this.isFavorite = false,
    this.notes = '',
    this.source = '',
    this.categoryId,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Recipe copyWith({
    String? id,
    String? title,
    String? description,
    List<String>? ingredients,
    List<String>? instructions,
    String? imageUrl,
    String? sourceUrl,
    String? userId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? tags,
    int? prepTime,
    int? cookTime,
    int? servings,
    bool? isFavorite,
    String? notes,
    String? source,
    String? categoryId,
  }) {
    return Recipe(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      ingredients: ingredients ?? this.ingredients,
      instructions: instructions ?? this.instructions,
      imageUrl: imageUrl ?? this.imageUrl,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
      prepTime: prepTime ?? this.prepTime,
      cookTime: cookTime ?? this.cookTime,
      servings: servings ?? this.servings,
      isFavorite: isFavorite ?? this.isFavorite,
      notes: notes ?? this.notes,
      source: source ?? this.source,
      categoryId: categoryId ?? this.categoryId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'ingredients': ingredients,
      'instructions': instructions,
      'imageUrl': imageUrl,
      'sourceUrl': sourceUrl,
      'userId': userId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'tags': tags,
      'prepTime': prepTime,
      'cookTime': cookTime,
      'servings': servings,
      'isFavorite': isFavorite,
      'notes': notes,
      'source': source,
      'categoryId': categoryId,
    };
  }

  factory Recipe.fromMap(Map<String, dynamic> map) {
    return Recipe(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String,
      ingredients: List<String>.from(map['ingredients']),
      instructions: List<String>.from(map['instructions']),
      imageUrl: map['imageUrl'] as String? ?? '',
      sourceUrl: map['sourceUrl'] as String? ?? '',
      userId: map['userId'] as String,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      updatedAt: (map['updatedAt'] as Timestamp).toDate(),
      tags: List<String>.from(map['tags'] ?? []),
      prepTime: map['prepTime'] as int? ?? 0,
      cookTime: map['cookTime'] as int? ?? 0,
      servings: map['servings'] as int? ?? 1,
      isFavorite: map['isFavorite'] as bool? ?? false,
      notes: map['notes'] as String? ?? '',
      source: map['source'] as String? ?? '',
      categoryId: map['categoryId'] as String?,
    );
  }

  @override
  String toString() {
    return 'Recipe(id: $id, title: $title, ingredients: ${ingredients.length}, instructions: ${instructions.length})';
  }

  // Create a Recipe from a Firestore document
  factory Recipe.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Recipe(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      ingredients: List<String>.from(data['ingredients'] ?? []),
      instructions: List<String>.from(data['instructions'] ?? []),
      imageUrl: data['imageUrl'] ?? '',
      sourceUrl: data['sourceUrl'] ?? '',
      userId: data['userId'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      tags: List<String>.from(data['tags'] ?? []),
      prepTime: data['prepTime'] ?? 0,
      cookTime: data['cookTime'] ?? 0,
      servings: data['servings'] ?? 1,
      isFavorite: data['isFavorite'] ?? false,
      notes: data['notes'] ?? '',
      source: data['source'] ?? '',
      categoryId: data['categoryId'] as String?,
    );
  }

  // Convert Recipe to a Map for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'ingredients': ingredients,
      'instructions': instructions,
      'imageUrl': imageUrl,
      'sourceUrl': sourceUrl,
      'userId': userId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'tags': tags,
      'prepTime': prepTime,
      'cookTime': cookTime,
      'servings': servings,
      'isFavorite': isFavorite,
      'notes': notes,
      'source': source,
      'categoryId': categoryId,
    };
  }
}
